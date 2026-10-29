"""API do Timesheet: login, projetos, usuários, lançamentos de horas e relatórios."""

import datetime as dt
import sqlite3
from contextlib import asynccontextmanager
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .db import connect, init_db
from .security import hash_password, new_token, verify_password

@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    yield


app = FastAPI(title="Timesheet API", version="0.1.0", lifespan=lifespan)

# O Flutter Web roda em outra porta do localhost durante o desenvolvimento.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------- modelos ----------

Role = Literal["tecnico", "gestor"]


class LoginIn(BaseModel):
    email: str
    password: str


class UserIn(BaseModel):
    name: str = Field(min_length=1)
    email: str = Field(min_length=3)
    password: str = Field(min_length=6)
    role: Role = "tecnico"


class ProjectIn(BaseModel):
    code: str = Field(min_length=1)
    name: str = Field(min_length=1)


class ProjectPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1)
    active: bool | None = None


class EntryIn(BaseModel):
    project_id: int
    work_date: dt.date
    hours: float = Field(gt=0, le=24)
    description: str = ""


# ---------- autenticação ----------


def current_user(authorization: str = Header(default="")) -> dict:
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Faça login.")
    with connect() as conn:
        row = conn.execute(
            """SELECT u.id, u.name, u.email, u.role FROM tokens t
               JOIN users u ON u.id = t.user_id
               WHERE t.token = ? AND u.active = 1""",
            (token,),
        ).fetchone()
    if row is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sessão inválida.")
    return dict(row)


def manager(user: dict = Depends(current_user)) -> dict:
    if user["role"] != "gestor":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Apenas gestores.")
    return user


@app.post("/auth/login")
def login(body: LoginIn):
    with connect() as conn:
        row = conn.execute(
            "SELECT * FROM users WHERE email = ? AND active = 1",
            (body.email.strip().lower(),),
        ).fetchone()
        if row is None or not verify_password(body.password, row["password_hash"]):
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "E-mail ou senha incorretos.")
        token = new_token()
        conn.execute("INSERT INTO tokens (token, user_id) VALUES (?, ?)", (token, row["id"]))
    user = {k: row[k] for k in ("id", "name", "email", "role")}
    return {"token": token, "user": user}


@app.post("/auth/logout", status_code=204)
def logout(authorization: str = Header(default="")):
    token = authorization.removeprefix("Bearer ").strip()
    with connect() as conn:
        conn.execute("DELETE FROM tokens WHERE token = ?", (token,))


@app.get("/me")
def me(user: dict = Depends(current_user)):
    return user


# ---------- usuários (gestor) ----------


@app.get("/users")
def list_users(_: dict = Depends(manager)):
    with connect() as conn:
        rows = conn.execute(
            "SELECT id, name, email, role, active FROM users ORDER BY name"
        ).fetchall()
    return [dict(r) | {"active": bool(r["active"])} for r in rows]


@app.post("/users", status_code=201)
def create_user(body: UserIn, _: dict = Depends(manager)):
    try:
        with connect() as conn:
            cur = conn.execute(
                "INSERT INTO users (name, email, password_hash, role) VALUES (?, ?, ?, ?)",
                (body.name.strip(), body.email.strip().lower(), hash_password(body.password), body.role),
            )
    except sqlite3.IntegrityError:
        raise HTTPException(status.HTTP_409_CONFLICT, "Já existe um usuário com esse e-mail.")
    return {"id": cur.lastrowid}


# ---------- projetos ----------


@app.get("/projects")
def list_projects(include_inactive: bool = False, _: dict = Depends(current_user)):
    sql = "SELECT id, code, name, active FROM projects"
    if not include_inactive:
        sql += " WHERE active = 1"
    with connect() as conn:
        rows = conn.execute(sql + " ORDER BY code").fetchall()
    return [dict(r) | {"active": bool(r["active"])} for r in rows]


@app.post("/projects", status_code=201)
def create_project(body: ProjectIn, _: dict = Depends(manager)):
    try:
        with connect() as conn:
            cur = conn.execute(
                "INSERT INTO projects (code, name) VALUES (?, ?)",
                (body.code.strip().upper(), body.name.strip()),
            )
    except sqlite3.IntegrityError:
        raise HTTPException(status.HTTP_409_CONFLICT, "Já existe um projeto com esse código.")
    return {"id": cur.lastrowid}


@app.patch("/projects/{project_id}")
def update_project(project_id: int, body: ProjectPatch, _: dict = Depends(manager)):
    with connect() as conn:
        if conn.execute("SELECT 1 FROM projects WHERE id = ?", (project_id,)).fetchone() is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Projeto não encontrado.")
        if body.name is not None:
            conn.execute("UPDATE projects SET name = ? WHERE id = ?", (body.name.strip(), project_id))
        if body.active is not None:
            conn.execute("UPDATE projects SET active = ? WHERE id = ?", (int(body.active), project_id))
    return {"ok": True}


# ---------- lançamentos ----------

ENTRY_SELECT = """
SELECT e.id, e.user_id, u.name AS user_name, e.project_id, p.code AS project_code,
       p.name AS project_name, e.work_date, e.hours, e.description
FROM entries e
JOIN users u ON u.id = e.user_id
JOIN projects p ON p.id = e.project_id
"""


def _check_active_project(conn, project_id: int) -> None:
    row = conn.execute("SELECT active FROM projects WHERE id = ?", (project_id,)).fetchone()
    if row is None or not row["active"]:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Projeto inexistente ou inativo.")


def _own_entry(conn, entry_id: int, user: dict):
    row = conn.execute("SELECT user_id FROM entries WHERE id = ?", (entry_id,)).fetchone()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Lançamento não encontrado.")
    if row["user_id"] != user["id"] and user["role"] != "gestor":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Esse lançamento não é seu.")


@app.get("/entries")
def list_entries(all_users: bool = False, user: dict = Depends(current_user)):
    """Técnico vê só os próprios lançamentos; gestor pode pedir os de todos."""
    with connect() as conn:
        if all_users and user["role"] == "gestor":
            rows = conn.execute(ENTRY_SELECT + " ORDER BY e.work_date DESC, e.id DESC").fetchall()
        else:
            rows = conn.execute(
                ENTRY_SELECT + " WHERE e.user_id = ? ORDER BY e.work_date DESC, e.id DESC",
                (user["id"],),
            ).fetchall()
    return [dict(r) for r in rows]


@app.post("/entries", status_code=201)
def create_entry(body: EntryIn, user: dict = Depends(current_user)):
    with connect() as conn:
        _check_active_project(conn, body.project_id)
        cur = conn.execute(
            "INSERT INTO entries (user_id, project_id, work_date, hours, description) VALUES (?, ?, ?, ?, ?)",
            (user["id"], body.project_id, body.work_date.isoformat(), body.hours, body.description.strip()),
        )
    return {"id": cur.lastrowid}


@app.put("/entries/{entry_id}")
def update_entry(entry_id: int, body: EntryIn, user: dict = Depends(current_user)):
    with connect() as conn:
        _own_entry(conn, entry_id, user)
        _check_active_project(conn, body.project_id)
        conn.execute(
            "UPDATE entries SET project_id = ?, work_date = ?, hours = ?, description = ? WHERE id = ?",
            (body.project_id, body.work_date.isoformat(), body.hours, body.description.strip(), entry_id),
        )
    return {"ok": True}


@app.delete("/entries/{entry_id}", status_code=204)
def delete_entry(entry_id: int, user: dict = Depends(current_user)):
    with connect() as conn:
        _own_entry(conn, entry_id, user)
        conn.execute("DELETE FROM entries WHERE id = ?", (entry_id,))


# ---------- relatórios (gestor) ----------


@app.get("/reports/by-project")
def report_by_project(_: dict = Depends(manager)):
    with connect() as conn:
        rows = conn.execute(
            """SELECT p.id, p.code, p.name, COALESCE(SUM(e.hours), 0) AS total_hours,
                      COUNT(DISTINCT e.user_id) AS people
               FROM projects p LEFT JOIN entries e ON e.project_id = p.id
               GROUP BY p.id ORDER BY total_hours DESC, p.code"""
        ).fetchall()
    return [dict(r) for r in rows]


@app.get("/reports/by-user")
def report_by_user(_: dict = Depends(manager)):
    with connect() as conn:
        rows = conn.execute(
            """SELECT u.id, u.name, COALESCE(SUM(e.hours), 0) AS total_hours,
                      COUNT(DISTINCT e.project_id) AS projects
               FROM users u LEFT JOIN entries e ON e.user_id = u.id
               WHERE u.active = 1
               GROUP BY u.id ORDER BY total_hours DESC, u.name"""
        ).fetchall()
    return [dict(r) for r in rows]
