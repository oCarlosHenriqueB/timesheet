"""Acesso ao banco. Sem ORM: SQL direto.

Local usa SQLite (arquivo timesheet.db). Em produção, defina DATABASE_URL
(postgresql://...) e o mesmo SQL roda no Postgres: os placeholders "?" são
trocados por "%s" e as linhas voltam como dicionários nos dois casos.
"""

import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path

DEFAULT_DB = Path(__file__).resolve().parent.parent / "timesheet.db"

SQLITE_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT NOT NULL,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role          TEXT NOT NULL CHECK (role IN ('tecnico', 'gestor')),
    active        INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS projects (
    id     INTEGER PRIMARY KEY AUTOINCREMENT,
    code   TEXT NOT NULL UNIQUE,
    name   TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS entries (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    project_id  INTEGER NOT NULL REFERENCES projects(id),
    work_date   TEXT NOT NULL,
    hours       REAL NOT NULL CHECK (hours > 0 AND hours <= 24),
    description TEXT NOT NULL DEFAULT '',
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS tokens (
    token      TEXT PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Cronômetro em andamento: no máximo um por usuário. Ao parar, vira um lançamento.
-- started_at em UTC (ISO 8601), para não depender do fuso do servidor.
CREATE TABLE IF NOT EXISTS timers (
    user_id     INTEGER PRIMARY KEY REFERENCES users(id),
    project_id  INTEGER NOT NULL REFERENCES projects(id),
    started_at  TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT ''
);

-- Cópia dos projetos do SAP, importada de um arquivo exportado do SAP.
-- Enquanto não houver conexão direta, é daqui que vem o "cliente automático".
CREATE TABLE IF NOT EXISTS sap_catalog (
    code            TEXT PRIMARY KEY,
    client          TEXT NOT NULL DEFAULT '',
    sap_wbs         TEXT NOT NULL DEFAULT '',
    sap_sales_order TEXT NOT NULL DEFAULT '',
    budget_hours    REAL,
    due_date        TEXT,
    imported_at     TEXT NOT NULL DEFAULT (datetime('now'))
);
"""

POSTGRES_SCHEMA = (
    SQLITE_SCHEMA.replace("INTEGER PRIMARY KEY AUTOINCREMENT", "SERIAL PRIMARY KEY")
    .replace("REAL", "DOUBLE PRECISION")
    .replace("TEXT NOT NULL DEFAULT (datetime('now'))", "TIMESTAMPTZ NOT NULL DEFAULT now()")
)


def database_url() -> str | None:
    return os.environ.get("DATABASE_URL") or None


def db_path() -> str:
    return os.environ.get("TIMESHEET_DB", str(DEFAULT_DB))


if database_url():
    import psycopg
    from psycopg.rows import dict_row

    IntegrityError: tuple[type[Exception], ...] = (sqlite3.IntegrityError, psycopg.IntegrityError)
else:
    IntegrityError = (sqlite3.IntegrityError,)


class _PgConnection:
    """Dá à conexão psycopg a mesma interface usada com sqlite3."""

    def __init__(self, url: str):
        self._conn = psycopg.connect(url, row_factory=dict_row)

    def execute(self, sql: str, params: tuple = ()):
        return self._conn.execute(sql.replace("?", "%s"), params)

    def executescript(self, script: str) -> None:
        for statement in script.split(";"):
            if statement.strip():
                self._conn.execute(statement)

    def commit(self) -> None:
        self._conn.commit()

    def close(self) -> None:
        self._conn.close()


def _sqlite_connection():
    conn = sqlite3.connect(db_path())
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


# Colunas adicionadas depois da v0.1. Bancos antigos ganham as colunas no
# próximo start; projetos existentes ficam sem horas previstas e sem data.
# client é texto livre por enquanto; no futuro poderá vir de um cadastro de
# clientes (ou do SAP) a partir do número do projeto.
MIGRATIONS = [
    ("projects", "client", "TEXT NOT NULL DEFAULT ''"),
    ("projects", "budget_hours", "REAL"),
    ("projects", "due_date", "TEXT"),
    # Referências para casar o projeto com o SAP (elemento PEP/WBS e ordem de venda).
    ("projects", "sap_wbs", "TEXT NOT NULL DEFAULT ''"),
    ("projects", "sap_sales_order", "TEXT NOT NULL DEFAULT ''"),
]


def _migrate(conn) -> None:
    pg = bool(database_url())
    for table, column, ddl in MIGRATIONS:
        if pg:
            ddl = ddl.replace("REAL", "DOUBLE PRECISION")
            conn.execute(f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS {column} {ddl}")
            continue
        existing = {r["name"] for r in conn.execute(f"PRAGMA table_info({table})")}
        if column not in existing:
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {ddl}")


def init_db() -> None:
    with connect() as conn:
        conn.executescript(POSTGRES_SCHEMA if database_url() else SQLITE_SCHEMA)
        _migrate(conn)


@contextmanager
def connect():
    url = database_url()
    conn = _PgConnection(url) if url else _sqlite_connection()
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()
