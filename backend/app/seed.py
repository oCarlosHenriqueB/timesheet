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
    ("Marina Costa", "gestor@exemplo.com", "gestor"),
    ("Ana Souza", "ana@exemplo.com", "tecnico"),  # "tecnico" = projetista nas telas
    ("Bruno Lima", "bruno@exemplo.com", "tecnico"),
    ("Carla Mendes", "carla@exemplo.com", "tecnico"),
]

# Clientes fictícios do segmento (montadoras, máquinas agrícolas e equipamentos pesados).
# (número, cliente, descrição, horas previstas, dias até a entrega)
PROJECTS = [
    ("PRJ-001", "Montadora Automotiva A", "Linha de aparafusamento de motores", 80, 30),
    ("PRJ-002", "Fabricante de Máquinas Agrícolas B", "Estação de aperto de chassis", 20, 5),
    ("PRJ-003", "Fabricante de Equipamentos Pesados C", "Retrofit de apertadeiras e integração ao PLC", 40, 15),
    ("INT-001", "Interno", "Treinamento interno", None, None),
]

# Equipe de cada projeto: (e-mail, número do projeto, horas previstas da pessoa, dias até o prazo dela).
# Prazo None = entrega do projeto. INT-001 fica sem equipe (aberto a todos).
ALLOCATIONS = [
    ("ana@exemplo.com", "PRJ-001", 60, 20),
    ("ana@exemplo.com", "PRJ-002", 14, None),
    ("bruno@exemplo.com", "PRJ-001", 40, None),
    ("bruno@exemplo.com", "PRJ-003", 24, 3),
    ("carla@exemplo.com", "PRJ-002", 20, 6),
    ("carla@exemplo.com", "PRJ-003", 30, None),
]

DESCRIPTIONS = [
    "Desenho do suporte da apertadeira",
    "Diagrama elétrico do painel",
    "Programação do controlador",
    "Ajuste de parâmetros de torque e ângulo",
    "Teste de aperto na linha",
    "Reunião de alinhamento com o cliente",
]


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
        user_by_email = {r["email"]: r["id"] for r in conn.execute("SELECT id, email FROM users")}
        project_by_code = {r["code"]: r["id"] for r in conn.execute("SELECT id, code FROM projects")}
        projects_of: dict[int, list[int]] = {}
        for email, code, budget, due_in in ALLOCATIONS:
            uid, pid = user_by_email[email], project_by_code[code]
            due = (today + dt.timedelta(days=due_in)).isoformat() if due_in is not None else None
            conn.execute(
                "INSERT INTO project_members (project_id, user_id, budget_hours, due_date) VALUES (?, ?, ?, ?)",
                (pid, uid, budget, due),
            )
            projects_of.setdefault(uid, []).append(pid)
        # Cada um aponta nos projetos em que está alocado (e às vezes no interno, que é aberto).
        for uid in tech_ids:
            projects_of.setdefault(uid, []).append(project_by_code["INT-001"])
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
                        (uid, rng.choice(projects_of[uid]), rng.choice(activity_ids), day.isoformat(),
                         start, end, pause, h, rng.choice(DESCRIPTIONS)),
                    )
    print(f"Dados de demonstração criados. Senha de todos: {DEMO_PASSWORD}")


if __name__ == "__main__":
    run()
