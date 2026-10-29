"""Popula o banco com dados FICTÍCIOS para demonstração. Uso: python -m app.seed"""

import datetime as dt
import random

from .db import connect, init_db
from .security import hash_password

DEMO_PASSWORD = "demo123"

USERS = [
    ("Gestora Demo", "gestor@exemplo.com", "gestor"),
    ("Ana Técnica", "ana@exemplo.com", "tecnico"),
    ("Bruno Engenheiro", "bruno@exemplo.com", "tecnico"),
    ("Carla Técnica", "carla@exemplo.com", "tecnico"),
]

PROJECTS = [
    ("PRJ-001", "Instalação de compressores - Cliente A"),
    ("PRJ-002", "Manutenção preventiva - Cliente B"),
    ("PRJ-003", "Documentação técnica e ART"),
    ("INT-001", "Treinamento interno"),
]

DESCRIPTIONS = ["Visita técnica", "Montagem", "Relatório", "Calibração", "Reunião com cliente"]


def run() -> None:
    init_db()
    with connect() as conn:
        if conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]:
            print("Banco já tem dados; nada a fazer.")
            return
        for name, email, role in USERS:
            conn.execute(
                "INSERT INTO users (name, email, password_hash, role) VALUES (?, ?, ?, ?)",
                (name, email, hash_password(DEMO_PASSWORD), role),
            )
        for code, name in PROJECTS:
            conn.execute("INSERT INTO projects (code, name) VALUES (?, ?)", (code, name))

        rng = random.Random(42)
        tech_ids = [r[0] for r in conn.execute("SELECT id FROM users WHERE role = 'tecnico'")]
        project_ids = [r[0] for r in conn.execute("SELECT id FROM projects")]
        today = dt.date.today()
        for days_ago in range(14):
            day = today - dt.timedelta(days=days_ago)
            if day.weekday() >= 5:
                continue
            for uid in tech_ids:
                conn.execute(
                    "INSERT INTO entries (user_id, project_id, work_date, hours, description) VALUES (?, ?, ?, ?, ?)",
                    (uid, rng.choice(project_ids), day.isoformat(), rng.choice([2, 4, 6, 8]), rng.choice(DESCRIPTIONS)),
                )
    print(f"Dados de demonstração criados. Senha de todos: {DEMO_PASSWORD}")


if __name__ == "__main__":
    run()
