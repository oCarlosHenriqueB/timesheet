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


def init_db() -> None:
    with connect() as conn:
        conn.executescript(POSTGRES_SCHEMA if database_url() else SQLITE_SCHEMA)


@contextmanager
def connect():
    url = database_url()
    conn = _PgConnection(url) if url else _sqlite_connection()
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()
