"""API do Timesheet: login, projetos, usuários, lançamentos de horas e relatórios."""

import datetime as dt
import os
from contextlib import asynccontextmanager
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Query, status
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, model_validator

from . import sap
from .db import IntegrityError, connect, init_db
from .security import hash_password, new_token, verify_password


def create_first_manager() -> None:
    """Em produção não há seed: se o banco está vazio, cria o gestor a partir
    de ADMIN_EMAIL / ADMIN_PASSWORD (variáveis de ambiente, nunca no código)."""
    email = os.environ.get("ADMIN_EMAIL", "").strip().lower()
    password = os.environ.get("ADMIN_PASSWORD", "")
    if not email or not password:
        return
    with connect() as conn:
        if conn.execute("SELECT COUNT(*) AS n FROM users").fetchone()["n"]:
            return
        conn.execute(
            "INSERT INTO users (name, email, password_hash, role) VALUES (?, ?, ?, 'gestor')",
            (os.environ.get("ADMIN_NAME", "Gestor"), email, hash_password(password)),
        )


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    create_first_manager()
    yield


app = FastAPI(title="Timesheet API", version="0.2.0", lifespan=lifespan)

# Em produção, CORS_ORIGINS lista só o domínio do front (ex.: https://usuario.github.io).
# Sem a variável, libera apenas o localhost, para o desenvolvimento.
_origins = [o.strip().rstrip("/") for o in os.environ.get("CORS_ORIGINS", "").split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_origin_regex=None if _origins else r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"ok": True}


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
    code: str = Field(min_length=1)  # número do projeto
    client: str = Field(min_length=1)
    name: str = ""  # descrição, opcional
    budget_hours: float | None = Field(default=None, gt=0)  # horas previstas
    due_date: dt.date | None = None  # data de entrega
    sap_wbs: str = ""  # elemento PEP no SAP
    sap_sales_order: str = ""  # ordem de venda no SAP


class ProjectPatch(BaseModel):
    """Só os campos enviados são alterados; budget_hours/due_date = null limpa o valor."""

    client: str | None = Field(default=None, min_length=1)
    name: str | None = None
    budget_hours: float | None = Field(default=None, gt=0)
    due_date: dt.date | None = None
    sap_wbs: str | None = None
    sap_sales_order: str | None = None
    active: bool | None = None


TIME_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d$"  # HH:MM, 24 h
STATUSES = ("rascunho", "enviado", "aprovado", "rejeitado")


def minutes(hhmm: str) -> int:
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


class EntryIn(BaseModel):
    """Apontamento. Com início e fim, as horas são calculadas (fim − início − intervalo);
    sem horários, vale o campo hours (lançamentos antigos e integrações)."""

    project_id: int
    activity_id: int | None = None
    work_date: dt.date
    start_time: str | None = Field(default=None, pattern=TIME_PATTERN)
    end_time: str | None = Field(default=None, pattern=TIME_PATTERN)
    break_minutes: int = Field(default=0, ge=0, le=12 * 60)
    hours: float | None = Field(default=None, gt=0, le=24)
    description: str = ""

    @model_validator(mode="after")
    def _resolve_hours(self):
        if (self.start_time is None) != (self.end_time is None):
            raise ValueError("Informe início e fim, ou nenhum dos dois.")
        if self.start_time and self.end_time:
            worked = minutes(self.end_time) - minutes(self.start_time) - self.break_minutes
            if minutes(self.end_time) <= minutes(self.start_time):
                raise ValueError("O fim precisa ser depois do início (no mesmo dia).")
            if worked <= 0:
                raise ValueError("O intervalo é maior que o período trabalhado.")
            self.hours = round(worked / 60, 2)
        elif self.hours is None:
            raise ValueError("Informe início e fim, ou o total de horas.")
        return self


# ---------- autenticação ----------


def current_user(authorization: str = Header(default="")) -> dict:
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Faça login.")
    with connect() as conn:
        row = conn.execute(
            """SELECT u.id, u.name, u.email, u.role, u.use_timer FROM tokens t
               JOIN users u ON u.id = t.user_id
               WHERE t.token = ? AND u.active = 1""",
            (token,),
        ).fetchone()
    if row is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sessão inválida.")
    return dict(row) | {"use_timer": bool(row["use_timer"])}


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
    user = {k: row[k] for k in ("id", "name", "email", "role")} | {"use_timer": bool(row["use_timer"])}
    return {"token": token, "user": user}


@app.post("/auth/logout", status_code=204)
def logout(authorization: str = Header(default="")):
    token = authorization.removeprefix("Bearer ").strip()
    with connect() as conn:
        conn.execute("DELETE FROM tokens WHERE token = ?", (token,))


@app.get("/me")
def me(user: dict = Depends(current_user)):
    return user


class PreferencesIn(BaseModel):
    use_timer: bool


@app.patch("/me/preferences")
def update_preferences(body: PreferencesIn, user: dict = Depends(current_user)):
    """Preferências de cada pessoa. Por enquanto: usar ou não o cronômetro."""
    with connect() as conn:
        conn.execute("UPDATE users SET use_timer = ? WHERE id = ?", (int(body.use_timer), user["id"]))
    return user | {"use_timer": body.use_timer}


# ---------- atividades ----------


class ActivityIn(BaseModel):
    name: str = Field(min_length=1)


class ActivityPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1)
    active: bool | None = None


@app.get("/activities")
def list_activities(include_inactive: bool = False, _: dict = Depends(current_user)):
    sql = "SELECT id, name, active FROM activities"
    if not include_inactive:
        sql += " WHERE active = 1"
    with connect() as conn:
        rows = conn.execute(sql + " ORDER BY name").fetchall()
    return [dict(r) | {"active": bool(r["active"])} for r in rows]


@app.post("/activities", status_code=201)
def create_activity(body: ActivityIn, _: dict = Depends(manager)):
    try:
        with connect() as conn:
            new_id = conn.execute(
                "INSERT INTO activities (name) VALUES (?) RETURNING id", (body.name.strip(),)
            ).fetchone()["id"]
    except IntegrityError:
        raise HTTPException(status.HTTP_409_CONFLICT, "Já existe uma atividade com esse nome.")
    return {"id": new_id}


@app.patch("/activities/{activity_id}")
def update_activity(activity_id: int, body: ActivityPatch, _: dict = Depends(manager)):
    try:
        with connect() as conn:
            if conn.execute("SELECT 1 FROM activities WHERE id = ?", (activity_id,)).fetchone() is None:
                raise HTTPException(status.HTTP_404_NOT_FOUND, "Atividade não encontrada.")
            if body.name is not None:
                conn.execute("UPDATE activities SET name = ? WHERE id = ?", (body.name.strip(), activity_id))
            if body.active is not None:
                conn.execute("UPDATE activities SET active = ? WHERE id = ?", (int(body.active), activity_id))
    except IntegrityError:
        raise HTTPException(status.HTTP_409_CONFLICT, "Já existe uma atividade com esse nome.")
    return {"ok": True}


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
            new_id = conn.execute(
                "INSERT INTO users (name, email, password_hash, role) VALUES (?, ?, ?, ?) RETURNING id",
                (body.name.strip(), body.email.strip().lower(), hash_password(body.password), body.role),
            ).fetchone()["id"]
    except IntegrityError:
        raise HTTPException(status.HTTP_409_CONFLICT, "Já existe um usuário com esse e-mail.")
    return {"id": new_id}


# ---------- projetos ----------


# Projeto com as horas já lançadas; o saldo (budget_hours - used_hours) e a
# cor de alerta são calculados no app.
PROJECT_SELECT = """
SELECT p.id, p.code, p.client, p.name, p.active, p.budget_hours, p.due_date, p.sap_wbs, p.sap_sales_order,
       COALESCE(u.used_hours, 0) AS used_hours, COALESCE(u.people, 0) AS people
FROM projects p
LEFT JOIN (
    SELECT project_id, SUM(hours) AS used_hours, COUNT(DISTINCT user_id) AS people
    FROM entries GROUP BY project_id
) u ON u.project_id = p.id
"""


def _project_json(r) -> dict:
    return dict(r) | {"active": bool(r["active"])}


@app.get("/projects")
def list_projects(include_inactive: bool = False, user: dict = Depends(current_user)):
    """Gestor vê todos. Projetista vê os projetos em que está alocado e os que não têm ninguém alocado."""
    sql = f"""SELECT x.*, COALESCE(m.members, 0) AS members
              FROM ({PROJECT_SELECT}) x
              LEFT JOIN (SELECT project_id, COUNT(*) AS members FROM project_members GROUP BY project_id) m
                     ON m.project_id = x.id
              WHERE 1 = 1"""
    params: list = []
    if not include_inactive:
        sql += " AND x.active = 1"
    if user["role"] != "gestor":
        sql += " AND (COALESCE(m.members, 0) = 0 OR x.id IN (SELECT project_id FROM project_members WHERE user_id = ?))"
        params.append(user["id"])
    with connect() as conn:
        rows = conn.execute(sql + " ORDER BY x.code", tuple(params)).fetchall()
    return [_project_json(r) for r in rows]


# ---------- alocação de projetistas (gestor) ----------


class MemberIn(BaseModel):
    user_id: int
    budget_hours: float | None = Field(default=None, gt=0)  # horas previstas para essa pessoa
    due_date: dt.date | None = None  # vazio = entrega do projeto


@app.get("/projects/{project_id}/members")
def list_members(project_id: int, _: dict = Depends(manager)):
    with connect() as conn:
        rows = conn.execute(
            """SELECT m.user_id, u.name AS user_name, m.budget_hours, m.due_date,
                      COALESCE((SELECT SUM(e.hours) FROM entries e
                                WHERE e.project_id = m.project_id AND e.user_id = m.user_id), 0) AS used_hours
               FROM project_members m JOIN users u ON u.id = m.user_id
               WHERE m.project_id = ? ORDER BY u.name""",
            (project_id,),
        ).fetchall()
    return [dict(r) for r in rows]


@app.put("/projects/{project_id}/members")
def replace_members(project_id: int, body: list[MemberIn], _: dict = Depends(manager)):
    """Define a equipe do projeto (substitui a lista). Lista vazia = projeto aberto a todos."""
    if len({m.user_id for m in body}) != len(body):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Projetista repetido na lista.")
    with connect() as conn:
        if conn.execute("SELECT 1 FROM projects WHERE id = ?", (project_id,)).fetchone() is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Projeto não encontrado.")
        for m in body:
            if conn.execute("SELECT 1 FROM users WHERE id = ? AND active = 1", (m.user_id,)).fetchone() is None:
                raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Usuário {m.user_id} não existe.")
        conn.execute("DELETE FROM project_members WHERE project_id = ?", (project_id,))
        for m in body:
            conn.execute(
                "INSERT INTO project_members (project_id, user_id, budget_hours, due_date) VALUES (?, ?, ?, ?)",
                (project_id, m.user_id, m.budget_hours, m.due_date.isoformat() if m.due_date else None),
            )
    return list_members(project_id)


@app.post("/projects", status_code=201)
def create_project(body: ProjectIn, _: dict = Depends(manager)):
    try:
        with connect() as conn:
            new_id = conn.execute(
                """INSERT INTO projects (code, client, name, budget_hours, due_date, sap_wbs, sap_sales_order)
                   VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id""",
                (
                    body.code.strip().upper(),
                    body.client.strip(),
                    body.name.strip(),
                    body.budget_hours,
                    body.due_date.isoformat() if body.due_date else None,
                    body.sap_wbs.strip(),
                    body.sap_sales_order.strip(),
                ),
            ).fetchone()["id"]
    except IntegrityError:
        raise HTTPException(status.HTTP_409_CONFLICT, "Já existe um projeto com esse número.")
    return {"id": new_id}


@app.patch("/projects/{project_id}")
def update_project(project_id: int, body: ProjectPatch, _: dict = Depends(manager)):
    changes = {}
    for field in body.model_fields_set:
        value = getattr(body, field)
        if field == "active":
            if value is not None:
                changes["active"] = int(value)
        elif field in ("client", "name", "sap_wbs", "sap_sales_order"):
            if value is not None:
                changes[field] = value.strip()
        elif field == "due_date":
            changes["due_date"] = value.isoformat() if value else None
        else:  # budget_hours
            changes["budget_hours"] = value
    with connect() as conn:
        if conn.execute("SELECT 1 FROM projects WHERE id = ?", (project_id,)).fetchone() is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Projeto não encontrado.")
        for column, value in changes.items():  # nomes vêm do modelo, não do usuário
            conn.execute(f"UPDATE projects SET {column} = ? WHERE id = ?", (value, project_id))
    return {"ok": True}


# ---------- lançamentos ----------

ENTRY_SELECT = """
SELECT e.id, e.user_id, u.name AS user_name, e.project_id, p.code AS project_code,
       p.name AS project_name, p.client AS project_client, e.activity_id, a.name AS activity_name,
       e.work_date, e.start_time, e.end_time, e.break_minutes, e.hours, e.description, e.status
FROM entries e
JOIN users u ON u.id = e.user_id
JOIN projects p ON p.id = e.project_id
LEFT JOIN activities a ON a.id = e.activity_id
"""


def _check_active_project(conn, project_id: int) -> None:
    row = conn.execute("SELECT active FROM projects WHERE id = ?", (project_id,)).fetchone()
    if row is None or not row["active"]:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Projeto inexistente ou inativo.")


def _check_allocated(conn, project_id: int, user: dict) -> None:
    """Projeto com equipe definida só aceita horas de quem está nela (o gestor pode tudo)."""
    if user["role"] == "gestor":
        return
    members = {r["user_id"] for r in conn.execute(
        "SELECT user_id FROM project_members WHERE project_id = ?", (project_id,))}
    if members and user["id"] not in members:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Você não está alocado neste projeto.")


def _check_activity(conn, activity_id: int | None) -> None:
    if activity_id is None:
        return
    row = conn.execute("SELECT active FROM activities WHERE id = ?", (activity_id,)).fetchone()
    if row is None or not row["active"]:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Atividade inexistente ou inativa.")


def _own_entry(conn, entry_id: int, user: dict):
    """Só o dono (ou o gestor) mexe; apontamento aprovado fica travado para o projetista."""
    row = conn.execute("SELECT user_id, status FROM entries WHERE id = ?", (entry_id,)).fetchone()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Lançamento não encontrado.")
    if user["role"] == "gestor":
        return
    if row["user_id"] != user["id"]:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Esse lançamento não é seu.")
    if row["status"] == "aprovado":
        raise HTTPException(status.HTTP_409_CONFLICT, "Apontamento aprovado não pode ser alterado.")


def period_filter(column: str, date_from: dt.date | None, date_to: dt.date | None) -> tuple[str, list]:
    """Trecho SQL " AND coluna >= ? AND coluna <= ?" para o período (datas inclusivas)."""
    sql, params = "", []
    if date_from:
        sql += f" AND {column} >= ?"
        params.append(date_from.isoformat())
    if date_to:
        sql += f" AND {column} <= ?"
        params.append(date_to.isoformat())
    return sql, params


@app.get("/entries")
def list_entries(
    all_users: bool = False,
    date_from: dt.date | None = None,
    date_to: dt.date | None = None,
    project_id: int | None = None,
    activity_id: int | None = None,
    status_: Literal[STATUSES] | None = Query(default=None, alias="status"),
    user_id: int | None = None,
    user: dict = Depends(current_user),
):
    """Projetista (papel "tecnico") vê só os próprios lançamentos; gestor pode pedir os de todos (ou de uma pessoa).
    Filtros opcionais: período, projeto, atividade e status."""
    where, params = period_filter("e.work_date", date_from, date_to)
    if user["role"] == "gestor" and (all_users or user_id is not None):
        if user_id is not None:
            where += " AND e.user_id = ?"
            params.append(user_id)
    else:
        where += " AND e.user_id = ?"
        params.append(user["id"])
    for column, value in (("e.project_id", project_id), ("e.activity_id", activity_id), ("e.status", status_)):
        if value is not None:
            where += f" AND {column} = ?"
            params.append(value)
    with connect() as conn:
        rows = conn.execute(
            ENTRY_SELECT + " WHERE 1 = 1" + where + " ORDER BY e.work_date DESC, e.start_time DESC, e.id DESC",
            tuple(params),
        ).fetchall()
    return [dict(r) for r in rows]


def _entry_values(body: EntryIn) -> tuple:
    return (
        body.project_id,
        body.activity_id,
        body.work_date.isoformat(),
        body.start_time,
        body.end_time,
        body.break_minutes if body.start_time else 0,
        body.hours,
        body.description.strip(),
    )


@app.post("/entries", status_code=201)
def create_entry(body: EntryIn, user: dict = Depends(current_user)):
    with connect() as conn:
        _check_active_project(conn, body.project_id)
        _check_allocated(conn, body.project_id, user)
        _check_activity(conn, body.activity_id)
        new_id = conn.execute(
            """INSERT INTO entries (project_id, activity_id, work_date, start_time, end_time, break_minutes,
                                    hours, description, user_id, status)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'enviado') RETURNING id""",
            (*_entry_values(body), user["id"]),
        ).fetchone()["id"]
    return {"id": new_id, "hours": body.hours}


@app.put("/entries/{entry_id}")
def update_entry(entry_id: int, body: EntryIn, user: dict = Depends(current_user)):
    with connect() as conn:
        _own_entry(conn, entry_id, user)
        _check_active_project(conn, body.project_id)
        current = conn.execute("SELECT project_id FROM entries WHERE id = ?", (entry_id,)).fetchone()
        if current["project_id"] != body.project_id:
            _check_allocated(conn, body.project_id, user)
        _check_activity(conn, body.activity_id)
        conn.execute(
            """UPDATE entries SET project_id = ?, activity_id = ?, work_date = ?, start_time = ?, end_time = ?,
                                  break_minutes = ?, hours = ?, description = ?
               WHERE id = ?""",
            (*_entry_values(body), entry_id),
        )
    return {"ok": True, "hours": body.hours}


@app.delete("/entries/{entry_id}", status_code=204)
def delete_entry(entry_id: int, user: dict = Depends(current_user)):
    with connect() as conn:
        _own_entry(conn, entry_id, user)
        conn.execute("DELETE FROM entries WHERE id = ?", (entry_id,))



# ---------- cronômetro ----------

MAX_TIMER_HOURS = 24


def utcnow() -> dt.datetime:
    """Separado para os testes poderem controlar o relógio."""
    return dt.datetime.now(dt.UTC)


class TimerStart(BaseModel):
    project_id: int
    activity_id: int | None = None
    description: str = ""


class TimerStop(BaseModel):
    work_date: dt.date  # dia em que começou, no fuso de quem lançou (o app manda)
    # Horário local de início e fim, só para mostrar no histórico; as horas vêm do tempo decorrido.
    start_time: str | None = Field(default=None, pattern=TIME_PATTERN)
    end_time: str | None = Field(default=None, pattern=TIME_PATTERN)
    description: str | None = None  # se vier, substitui a do início


def _timer_json(row) -> dict:
    started = dt.datetime.fromisoformat(row["started_at"])
    elapsed = int((utcnow() - started).total_seconds())
    return dict(row) | {"elapsed_seconds": max(elapsed, 0)}


@app.get("/timer")
def get_timer(user: dict = Depends(current_user)):
    """Cronômetro em andamento do usuário, ou null."""
    with connect() as conn:
        row = conn.execute(
            """SELECT t.project_id, p.code AS project_code, p.client AS project_client, t.activity_id,
                      a.name AS activity_name, t.started_at, t.description
               FROM timers t JOIN projects p ON p.id = t.project_id
               LEFT JOIN activities a ON a.id = t.activity_id
               WHERE t.user_id = ?""",
            (user["id"],),
        ).fetchone()
    return _timer_json(row) if row else None


@app.post("/timer", status_code=201)
def start_timer(body: TimerStart, user: dict = Depends(current_user)):
    with connect() as conn:
        _check_active_project(conn, body.project_id)
        _check_allocated(conn, body.project_id, user)
        _check_activity(conn, body.activity_id)
        if conn.execute("SELECT 1 FROM timers WHERE user_id = ?", (user["id"],)).fetchone():
            raise HTTPException(status.HTTP_409_CONFLICT, "Já existe um cronômetro rodando. Pare ou descarte antes.")
        conn.execute(
            "INSERT INTO timers (user_id, project_id, activity_id, started_at, description) VALUES (?, ?, ?, ?, ?)",
            (user["id"], body.project_id, body.activity_id, utcnow().isoformat(), body.description.strip()),
        )
    return get_timer(user)


@app.post("/timer/stop", status_code=201)
def stop_timer(body: TimerStop, user: dict = Depends(current_user)):
    """Para o cronômetro e cria o lançamento com as horas decorridas (2 casas decimais)."""
    with connect() as conn:
        row = conn.execute("SELECT * FROM timers WHERE user_id = ?", (user["id"],)).fetchone()
        if row is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Nenhum cronômetro rodando.")
        seconds = (utcnow() - dt.datetime.fromisoformat(row["started_at"])).total_seconds()
        if seconds < 60:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Menos de 1 minuto: descarte o cronômetro.")
        if seconds > MAX_TIMER_HOURS * 3600:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_CONTENT,
                "O cronômetro passou de 24 h (esqueceu ligado?). Descarte e lance as horas à mão.",
            )
        _check_active_project(conn, row["project_id"])
        hours = round(seconds / 3600, 2)
        description = (body.description if body.description is not None else row["description"]).strip()
        new_id = conn.execute(
            """INSERT INTO entries (user_id, project_id, activity_id, work_date, start_time, end_time,
                                    hours, description, status)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'enviado') RETURNING id""",
            (
                user["id"],
                row["project_id"],
                row["activity_id"],
                body.work_date.isoformat(),
                body.start_time,
                body.end_time,
                hours,
                description,
            ),
        ).fetchone()["id"]
        conn.execute("DELETE FROM timers WHERE user_id = ?", (user["id"],))
    return {"id": new_id, "hours": hours}


@app.delete("/timer", status_code=204)
def discard_timer(user: dict = Depends(current_user)):
    with connect() as conn:
        conn.execute("DELETE FROM timers WHERE user_id = ?", (user["id"],))

# ---------- dashboard ----------


@app.get("/dashboard")
def dashboard(today: dt.date | None = None, user: dict = Depends(current_user)):
    """Resumo para a tela inicial. `today` vem do app (data local de quem usa)."""
    today = today or utcnow().date()
    monday = today - dt.timedelta(days=today.weekday())
    week = [monday + dt.timedelta(days=i) for i in range(7)]
    with connect() as conn:
        per_day = {
            r["work_date"]: r["hours"]
            for r in conn.execute(
                """SELECT work_date, SUM(hours) AS hours FROM entries
                   WHERE user_id = ? AND work_date >= ? AND work_date <= ? GROUP BY work_date""",
                (user["id"], week[0].isoformat(), week[-1].isoformat()),
            )
        }
        month_hours = conn.execute(
            "SELECT COALESCE(SUM(hours), 0) AS h FROM entries WHERE user_id = ? AND work_date >= ? AND work_date <= ?",
            (user["id"], today.replace(day=1).isoformat(), today.isoformat()),
        ).fetchone()["h"]
        # Projetos em andamento: ativos e com lançamento nos últimos 30 dias (meus; do time, para o gestor).
        since = (today - dt.timedelta(days=30)).isoformat()
        mine = "" if user["role"] == "gestor" else " AND user_id = ?"
        params = (since,) if user["role"] == "gestor" else (since, user["id"])
        projects = conn.execute(
            f"""SELECT x.* FROM ({PROJECT_SELECT}) x
                WHERE x.active = 1 AND x.id IN (SELECT project_id FROM entries WHERE work_date >= ?{mine})
                ORDER BY x.code""",
            params,
        ).fetchall()
        recent = conn.execute(
            ENTRY_SELECT + " WHERE e.user_id = ? ORDER BY e.work_date DESC, e.start_time DESC, e.id DESC LIMIT 6",
            (user["id"],),
        ).fetchall()
        team_week = None
        if user["role"] == "gestor":
            team_week = conn.execute(
                "SELECT COALESCE(SUM(hours), 0) AS h FROM entries WHERE work_date >= ? AND work_date <= ?",
                (week[0].isoformat(), week[-1].isoformat()),
            ).fetchone()["h"]
    week_days = [{"date": d.isoformat(), "hours": per_day.get(d.isoformat(), 0)} for d in week]
    return {
        "today": today.isoformat(),
        "today_hours": per_day.get(today.isoformat(), 0),
        "week_hours": sum(d["hours"] for d in week_days),
        "month_hours": month_hours,
        "week_days": week_days,
        "projects_in_progress": [_project_json(r) for r in projects],
        "recent_entries": [dict(r) for r in recent],
        "team_week_hours": team_week,
    }


# ---------- relatórios (gestor) ----------


@app.get("/reports/team-grid")
def team_grid(date_from: dt.date, date_to: dt.date, _: dict = Depends(manager)):
    """Grade colaborador × projeto × dia. Uma linha para cada alocação em projeto ativo e para cada
    par pessoa/projeto com horas no período. As cores são calculadas no app a partir de:
    horas previstas e prazo da pessoa (ou do projeto), horas antes do período e horas por dia."""
    if date_to < date_from or (date_to - date_from).days > 62:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Período inválido (máximo de 62 dias).")
    with connect() as conn:
        pairs = {
            (r["user_id"], r["project_id"]): dict(r)
            for r in conn.execute(
                """SELECT m.user_id, m.project_id, m.budget_hours, m.due_date, 1 AS allocated
                   FROM project_members m JOIN projects p ON p.id = m.project_id JOIN users u ON u.id = m.user_id
                   WHERE p.active = 1 AND u.active = 1"""
            )
        }
        daily = conn.execute(
            """SELECT user_id, project_id, work_date, SUM(hours) AS hours FROM entries
               WHERE work_date >= ? AND work_date <= ? GROUP BY user_id, project_id, work_date""",
            (date_from.isoformat(), date_to.isoformat()),
        ).fetchall()
        for d in daily:
            pairs.setdefault((d["user_id"], d["project_id"]),
                             {"user_id": d["user_id"], "project_id": d["project_id"],
                              "budget_hours": None, "due_date": None, "allocated": 0})
        before = {
            (r["user_id"], r["project_id"]): r["hours"]
            for r in conn.execute(
                "SELECT user_id, project_id, SUM(hours) AS hours FROM entries WHERE work_date < ? GROUP BY user_id, project_id",
                (date_from.isoformat(),),
            )
        }
        totals = {
            (r["user_id"], r["project_id"]): r["hours"]
            for r in conn.execute("SELECT user_id, project_id, SUM(hours) AS hours FROM entries GROUP BY user_id, project_id")
        }
        users = {r["id"]: r["name"] for r in conn.execute("SELECT id, name FROM users")}
        projects = {r["id"]: dict(r) for r in conn.execute("SELECT id, code, client, name, due_date FROM projects")}
    days_by_pair: dict = {}
    for d in daily:
        days_by_pair.setdefault((d["user_id"], d["project_id"]), {})[d["work_date"]] = d["hours"]
    rows = []
    for (uid, pid), a in pairs.items():
        proj = projects[pid]
        rows.append({
            "user_id": uid,
            "user_name": users[uid],
            "project_id": pid,
            "project_code": proj["code"],
            "project_client": proj["client"],
            "project_name": proj["name"],
            "allocated": bool(a["allocated"]),
            "budget_hours": a["budget_hours"],
            "due_date": a["due_date"] or proj["due_date"],
            "hours_before": before.get((uid, pid), 0),
            "total_hours": totals.get((uid, pid), 0),
            "days": days_by_pair.get((uid, pid), {}),
        })
    rows.sort(key=lambda r: (r["user_name"], r["project_code"]))
    n = (date_to - date_from).days + 1
    return {"days": [(date_from + dt.timedelta(days=i)).isoformat() for i in range(n)], "rows": rows}


@app.get("/reports/by-activity")
def report_by_activity(
    date_from: dt.date | None = None, date_to: dt.date | None = None, _: dict = Depends(manager)
):
    where, params = period_filter("e.work_date", date_from, date_to)
    with connect() as conn:
        rows = conn.execute(
            f"""SELECT COALESCE(a.name, 'Sem atividade') AS name, SUM(e.hours) AS total_hours,
                       COUNT(DISTINCT e.project_id) AS projects
                FROM entries e LEFT JOIN activities a ON a.id = e.activity_id
                WHERE 1 = 1{where}
                GROUP BY COALESCE(a.name, 'Sem atividade') ORDER BY total_hours DESC""",
            tuple(params),
        ).fetchall()
    return [dict(r) for r in rows]


@app.get("/reports/by-project")
def report_by_project(
    date_from: dt.date | None = None, date_to: dt.date | None = None, _: dict = Depends(manager)
):
    """total_hours = horas no período; used_hours (base do saldo) é sempre o total do projeto."""
    where, params = period_filter("work_date", date_from, date_to)
    sql = f"""SELECT x.*, COALESCE(pp.period_hours, 0) AS total_hours, COALESCE(pp.period_people, 0) AS period_people
              FROM ({PROJECT_SELECT}) x
              LEFT JOIN (
                  SELECT project_id, SUM(hours) AS period_hours, COUNT(DISTINCT user_id) AS period_people
                  FROM entries WHERE 1 = 1{where} GROUP BY project_id
              ) pp ON pp.project_id = x.id
              ORDER BY total_hours DESC, x.code"""
    with connect() as conn:
        rows = conn.execute(sql, tuple(params)).fetchall()
    return [_project_json(r) for r in rows]


@app.get("/reports/by-user")
def report_by_user(
    date_from: dt.date | None = None, date_to: dt.date | None = None, _: dict = Depends(manager)
):
    where, params = period_filter("e.work_date", date_from, date_to)
    with connect() as conn:
        rows = conn.execute(
            f"""SELECT u.id, u.name, COALESCE(SUM(e.hours), 0) AS total_hours,
                       COUNT(DISTINCT e.project_id) AS projects
                FROM users u LEFT JOIN entries e ON e.user_id = u.id{where}
                WHERE u.active = 1
                GROUP BY u.id ORDER BY total_hours DESC, u.name""",
            tuple(params),
        ).fetchall()
    return [dict(r) for r in rows]


# ---------- SAP (veja app/sap.py) ----------


class CatalogIn(BaseModel):
    csv: str


@app.get("/sap/projects/{code}")
def sap_lookup_project(code: str, _: dict = Depends(manager)):
    """Busca no SAP os dados do projeto pelo número, para preencher o cadastro."""
    with connect() as conn:
        try:
            found = sap.lookup_project(conn, code)
        except sap.SapNotConfigured as e:
            raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, str(e))
    if found is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Projeto não encontrado no catálogo do SAP.")
    return found


@app.post("/sap/catalog")
def sap_import_catalog(body: CatalogIn, _: dict = Depends(manager)):
    """Importa o catálogo de projetos exportado do SAP (CSV ou colado do Excel)."""
    rows, errors = sap.parse_catalog(body.csv)
    with connect() as conn:
        imported = sap.import_catalog(conn, rows)
    return {"imported": imported, "errors": errors}


@app.get("/sap/catalog/template")
def sap_catalog_template(_: dict = Depends(manager)):
    return {"columns": sap.CATALOG_TEMPLATE.strip()}


@app.get("/exports/entries.csv")
def export_entries(date_from: dt.date | None = None, date_to: dt.date | None = None, _: dict = Depends(manager)):
    """Lançamentos do período em CSV, num layout próximo ao do apontamento de horas do SAP (CATS)."""
    sql = """SELECT e.work_date, e.hours, e.description, e.start_time, e.end_time, e.break_minutes, e.status,
                    a.name AS activity_name, p.code AS project_code, p.client,
                    p.sap_wbs, p.sap_sales_order, u.name AS user_name, u.email AS user_email
             FROM entries e JOIN users u ON u.id = e.user_id JOIN projects p ON p.id = e.project_id
             LEFT JOIN activities a ON a.id = e.activity_id
             WHERE 1 = 1"""
    where, params = period_filter("e.work_date", date_from, date_to)
    sql += where
    with connect() as conn:
        rows = [dict(r) for r in conn.execute(sql + " ORDER BY e.work_date, u.name", tuple(params)).fetchall()]
    name = f"horas_{date_from or 'inicio'}_{date_to or 'hoje'}.csv"
    return Response(
        sap.export_entries_csv(rows),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{name}"'},
    )
