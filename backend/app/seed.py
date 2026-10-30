"""Popula o banco com dados FICTÍCIOS para demonstração. Uso: python -m app.seed"""

import datetime as dt
import os
import random
import sys

from pathlib import Path

from . import sap
from .db import connect, database_url, init_db
from .security import hash_password

CATALOG_EXAMPLE = Path(__file__).resolve().parents[2] / "docs" / "catalogo_sap_exemplo.csv"

DEMO_PASSWORD = os.environ.get("SEED_PASSWORD", "demo123")

USERS = [
    ("Gestora Demo", "gestor@exemplo.com", "gestor"),
    ("Ana Técnica", "ana@exemplo.com", "tecnico"),
    ("Bruno Engenheiro", "bruno@exemplo.com", "tecnico"),
    ("Carla Técnica", "carla@exemplo.com", "tecnico"),
]

# (número, cliente, descrição, horas previstas, dias até a entrega)
PROJECTS = [
    ("PRJ-001", "Hospital Exemplo A", "Instalação de compressores", 80, 30),
    ("PRJ-002", "Indústria Exemplo B", "Manutenção preventiva", 20, 5),
    ("PRJ-003", "Clínica Exemplo C", "Documentação técnica e ART", 40, 15),
    ("INT-001", "Interno", "Treinamento interno", None, None),
]

DESCRIPTIONS = ["Visita técnica", "Montagem", "Relatório", "Calibração", "Reunião com cliente"]


def run() -> None:
    if database_url() and "SEED_PASSWORD" not in os.environ:
        sys.exit("Banco remoto: defina SEED_PASSWORD para não publicar a senha padrão demo123.")
    init_db()
    with connect() as conn:
        if conn.execute("SELECT COUNT(*) AS n FROM users").fetchone()["n"]:
            print("Banco já tem dados; nada a fazer.")
            return
        for name, email, role in USERS:
            conn.execute(
                "INSERT INTO users (name, email, password_hash, role) VALUES (?, ?, ?, ?)",
                (name, email, hash_password(DEMO_PASSWORD), role),
            )
        today = dt.date.today()
        for code, client, name, budget, due_in in PROJECTS:
            due = (today + dt.timedelta(days=due_in)).isoformat() if due_in is not None else None
            conn.execute(
                "INSERT INTO projects (code, client, name, budget_hours, due_date, sap_wbs) VALUES (?, ?, ?, ?, ?, ?)",
                (code, client, name, budget, due, f"BR-{code}-01" if code.startswith("PRJ") else ""),
            )
        if CATALOG_EXAMPLE.exists():  # catálogo SAP fictício, para testar o "buscar no SAP"
            rows, _ = sap.parse_catalog(CATALOG_EXAMPLE.read_text(encoding="utf-8"))
            sap.import_catalog(conn, rows)

        rng = random.Random(42)
        tech_ids = [r["id"] for r in conn.execute("SELECT id FROM users WHERE role = 'tecnico'")]
        project_ids = [r["id"] for r in conn.execute("SELECT id FROM projects")]
        activity_ids = [r["id"] for r in conn.execute("SELECT id FROM activities WHERE name <> 'Outros'")]
        for days_ago in range(14):
            day = today - dt.timedelta(days=days_ago)
            if day.weekday() >= 5:
                continue
            for uid in tech_ids:
                # Manhã (08:00 a 12:00) e, em alguns dias, tarde com intervalo de 15 min.
                blocks = [("08:00", "12:00", 0)] + ([("13:00", "17:15", 15)] if rng.random() < 0.6 else [])
                for start, end, pause in blocks:
                    h = (int(end[:2]) * 60 + int(end[3:]) - int(start[:2]) * 60 - int(start[3:]) - pause) / 60
                    conn.execute(
                        """INSERT INTO entries (user_id, project_id, activity_id, work_date, start_time, end_time,
                                                break_minutes, hours, description)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                        (uid, rng.choice(project_ids), rng.choice(activity_ids), day.isoformat(),
                         start, end, pause, h, rng.choice(DESCRIPTIONS)),
                    )
    print(f"Dados de demonstração criados. Senha de todos: {DEMO_PASSWORD}")


if __name__ == "__main__":
    run()
