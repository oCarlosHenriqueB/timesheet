import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client(tmp_path, monkeypatch):
    """SQLite temporário por padrão. Com DATABASE_URL definida, roda contra esse
    Postgres, apagando as tabelas antes de cada teste (use um banco de teste!)."""
    from app import db, seed
    from app.main import app

    monkeypatch.setenv("TIMESHEET_DB", str(tmp_path / "test.db"))
    if db.database_url():
        monkeypatch.setenv("SEED_PASSWORD", "demo123")
        with db.connect() as conn:
            conn.execute("DROP TABLE IF EXISTS tokens, timers, entries, projects, users, sap_catalog, activities, app_meta")
    seed.run()
    with TestClient(app) as c:
        yield c


def login(client, email):
    r = client.post("/auth/login", json={"email": email, "password": "demo123"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def test_login_errado(client):
    r = client.post("/auth/login", json={"email": "ana@exemplo.com", "password": "x"})
    assert r.status_code == 401


def test_sem_token(client):
    assert client.get("/entries").status_code == 401


def test_tecnico_lanca_e_ve_so_os_proprios(client):
    ana = login(client, "ana@exemplo.com")
    project_id = client.get("/projects", headers=ana).json()[0]["id"]
    r = client.post(
        "/entries",
        headers=ana,
        json={"project_id": project_id, "work_date": "2026-10-01", "hours": 3.5, "description": "Teste"},
    )
    assert r.status_code == 201
    entries = client.get("/entries", headers=ana).json()
    assert {e["user_name"] for e in entries} == {"Ana Souza"}
    # all_users é ignorado para técnico
    assert client.get("/entries?all_users=true", headers=ana).json() == entries


def test_horas_invalidas(client):
    ana = login(client, "ana@exemplo.com")
    project_id = client.get("/projects", headers=ana).json()[0]["id"]
    for hours in (0, -1, 25):
        r = client.post("/entries", headers=ana, json={"project_id": project_id, "work_date": "2026-10-01", "hours": hours})
        assert r.status_code == 422


def test_nao_edita_lancamento_alheio(client):
    ana = login(client, "ana@exemplo.com")
    bruno = login(client, "bruno@exemplo.com")
    entry = client.get("/entries", headers=bruno).json()[0]
    assert client.delete(f"/entries/{entry['id']}", headers=ana).status_code == 403
    assert client.delete(f"/entries/{entry['id']}", headers=bruno).status_code == 204


def test_projeto_inativo_nao_aceita_lancamento(client):
    gestor = login(client, "gestor@exemplo.com")
    ana = login(client, "ana@exemplo.com")
    pid = client.post("/projects", headers=gestor, json={"code": "tmp-1", "client": "Cliente X"}).json()["id"]
    client.patch(f"/projects/{pid}", headers=gestor, json={"active": False})
    r = client.post("/entries", headers=ana, json={"project_id": pid, "work_date": "2026-10-01", "hours": 1})
    assert r.status_code == 422


def test_relatorios_somam_horas(client):
    gestor = login(client, "gestor@exemplo.com")
    ana = login(client, "ana@exemplo.com")
    assert client.get("/reports/by-project", headers=ana).status_code == 403

    all_entries = client.get("/entries?all_users=true", headers=gestor).json()
    total = sum(e["hours"] for e in all_entries)
    by_project = client.get("/reports/by-project", headers=gestor).json()
    by_user = client.get("/reports/by-user", headers=gestor).json()
    assert sum(p["total_hours"] for p in by_project) == pytest.approx(total)
    assert sum(u["total_hours"] for u in by_user) == pytest.approx(total)


def test_gestor_cria_usuario(client):
    gestor = login(client, "gestor@exemplo.com")
    body = {"name": "Novo", "email": "Novo@Exemplo.com", "password": "segredo1"}
    assert client.post("/users", headers=gestor, json=body).status_code == 201
    assert client.post("/users", headers=gestor, json=body).status_code == 409
    r = client.post("/auth/login", json={"email": "novo@exemplo.com", "password": "segredo1"})
    assert r.status_code == 200


def test_primeiro_gestor_vem_do_ambiente(tmp_path, monkeypatch):
    from app import db
    from app.main import app

    if db.database_url():
        pytest.skip("teste só para SQLite")
    monkeypatch.setenv("TIMESHEET_DB", str(tmp_path / "vazio.db"))
    monkeypatch.setenv("ADMIN_EMAIL", "Chefe@Exemplo.com")
    monkeypatch.setenv("ADMIN_PASSWORD", "segredo-forte")
    with TestClient(app) as c:
        r = c.post("/auth/login", json={"email": "chefe@exemplo.com", "password": "segredo-forte"})
        assert r.status_code == 200
        assert r.json()["user"]["role"] == "gestor"
        assert c.get("/health").json() == {"ok": True}


def test_projeto_com_cliente_horas_previstas_e_entrega(client):
    gestor = login(client, "gestor@exemplo.com")
    ana = login(client, "ana@exemplo.com")
    body = {"code": "prj-900", "client": "Hospital Z", "budget_hours": 10, "due_date": "2026-12-01"}
    pid = client.post("/projects", headers=gestor, json=body).json()["id"]
    client.post("/entries", headers=ana, json={"project_id": pid, "work_date": "2026-10-01", "hours": 4})

    p = next(p for p in client.get("/projects", headers=ana).json() if p["id"] == pid)
    assert (p["code"], p["client"], p["name"]) == ("PRJ-900", "Hospital Z", "")
    assert (p["budget_hours"], p["used_hours"], p["due_date"]) == (10, 4, "2026-12-01")

    # Número repetido e campos obrigatórios/invalidos
    assert client.post("/projects", headers=gestor, json=body).status_code == 409
    assert client.post("/projects", headers=gestor, json={"code": "X"}).status_code == 422
    assert client.post("/projects", headers=gestor, json=body | {"code": "Y", "budget_hours": 0}).status_code == 422


def test_editar_projeto_so_altera_campos_enviados(client):
    gestor = login(client, "gestor@exemplo.com")
    body = {"code": "prj-901", "client": "A", "name": "Desc", "budget_hours": 10, "due_date": "2026-12-01"}
    pid = client.post("/projects", headers=gestor, json=body).json()["id"]

    assert client.patch(f"/projects/{pid}", headers=gestor, json={"client": "B", "budget_hours": None}).status_code == 200
    p = next(p for p in client.get("/projects", headers=gestor).json() if p["id"] == pid)
    assert (p["client"], p["name"], p["budget_hours"], p["due_date"]) == ("B", "Desc", None, "2026-12-01")


def test_relatorio_por_projeto_traz_orcamento(client):
    gestor = login(client, "gestor@exemplo.com")
    rows = client.get("/reports/by-project", headers=gestor).json()
    assert {"client", "budget_hours", "due_date", "used_hours", "total_hours", "people"} <= rows[0].keys()


def test_banco_antigo_ganha_colunas_novas(tmp_path, monkeypatch):
    import sqlite3

    from app import db

    if db.database_url():
        pytest.skip("teste só para SQLite")
    path = tmp_path / "antigo.db"
    old = sqlite3.connect(path)
    old.execute("CREATE TABLE projects (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1)")
    old.execute("INSERT INTO projects (code, name) VALUES ('OLD-1', 'Antigo')")
    old.execute("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL, role TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1)")
    old.execute("INSERT INTO users (name, email, password_hash, role) VALUES ('Ana', 'ana@x.com', 'h', 'tecnico')")
    old.execute("CREATE TABLE entries (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, project_id INTEGER NOT NULL, work_date TEXT NOT NULL, hours REAL NOT NULL, description TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT (datetime('now')))")
    old.execute("INSERT INTO entries (user_id, project_id, work_date, hours) VALUES (1, 1, '2026-10-01', 3.5)")
    old.commit()
    old.close()

    monkeypatch.setenv("TIMESHEET_DB", str(path))
    db.init_db()
    db.init_db()  # rodar duas vezes não pode falhar
    with db.connect() as conn:
        row = dict(conn.execute("SELECT * FROM projects").fetchone())
        entries = [dict(r) for r in conn.execute("SELECT project_id, hours FROM entries")]
    assert row["client"] == "" and row["budget_hours"] is None and row["due_date"] is None
    assert entries == [{"project_id": 1, "hours": 3.5}]  # lançamentos antigos preservados


# ---------- SAP ----------


def test_catalogo_sap_importa_e_busca(client):
    gestor = login(client, "gestor@exemplo.com")
    ana = login(client, "ana@exemplo.com")
    # O seed já importou docs/catalogo_sap_exemplo.csv
    r = client.get("/sap/projects/prj-005", headers=gestor)
    assert r.status_code == 200
    assert r.json() == {
        "code": "PRJ-005", "client": "Fabricante de Implementos Agrícolas E", "sap_wbs": "BR-PRJ-005-01",
        "sap_sales_order": "4500001005", "budget_hours": 35.5, "due_date": "2026-11-30",
    }
    assert client.get("/sap/projects/NAO-EXISTE", headers=gestor).status_code == 404
    assert client.get("/sap/projects/PRJ-005", headers=ana).status_code == 403

    # Colado do Excel (tab), atualiza um existente e acusa linhas ruins sem travar as boas
    pasted = "Projeto\tCliente\tHoras_previstas\tData_entrega\nPRJ-005\tCliente Novo\t1.234,5\t01/02/2027\nPRJ-007\tX\tabc\t\nPRJ-008\tY\t10\t31/02/2027\n"
    r = client.post("/sap/catalog", headers=gestor, json={"csv": pasted}).json()
    assert r["imported"] == 1 and len(r["errors"]) == 2
    found = client.get("/sap/projects/PRJ-005", headers=gestor).json()
    assert (found["client"], found["budget_hours"], found["due_date"]) == ("Cliente Novo", 1234.5, "2027-02-01")


def test_catalogo_sem_colunas_obrigatorias(client):
    gestor = login(client, "gestor@exemplo.com")
    r = client.post("/sap/catalog", headers=gestor, json={"csv": "numero;nome\n1;a\n"}).json()
    assert r["imported"] == 0 and "Faltam as colunas" in r["errors"][0]


def test_provedor_sap_direto_ainda_nao_existe(client, monkeypatch):
    gestor = login(client, "gestor@exemplo.com")
    monkeypatch.setenv("SAP_PROVIDER", "odata")
    assert client.get("/sap/projects/PRJ-001", headers=gestor).status_code == 501


def test_projeto_guarda_referencias_sap(client):
    gestor = login(client, "gestor@exemplo.com")
    body = {"code": "prj-950", "client": "C", "sap_wbs": "BR-950", "sap_sales_order": "450"}
    pid = client.post("/projects", headers=gestor, json=body).json()["id"]
    client.patch(f"/projects/{pid}", headers=gestor, json={"sap_sales_order": "451"})
    p = next(p for p in client.get("/projects", headers=gestor).json() if p["id"] == pid)
    assert (p["sap_wbs"], p["sap_sales_order"]) == ("BR-950", "451")


def test_exporta_horas_csv_por_periodo(client):
    gestor = login(client, "gestor@exemplo.com")
    ana = login(client, "ana@exemplo.com")
    pid = client.post("/projects", headers=gestor, json={"code": "EXP-1", "client": "Cliente; com ponto e vírgula", "sap_wbs": "BR-EXP"}).json()["id"]
    client.post("/entries", headers=ana, json={"project_id": pid, "work_date": "2020-01-15", "hours": 2.5, "description": "Visita"})
    client.post("/entries", headers=ana, json={"project_id": pid, "work_date": "2020-03-01", "hours": 1})

    r = client.get("/exports/entries.csv?date_from=2020-01-01&date_to=2020-01-31", headers=gestor)
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/csv")
    lines = r.content.decode("utf-8-sig").splitlines()
    assert lines[0] == (
        "data;projeto;pep;ordem_venda;cliente;funcionario;email;atividade;inicio;fim;intervalo_min;horas;status;descricao"
    )
    assert lines[1:] == [
        '15.01.2020;EXP-1;BR-EXP;;"Cliente; com ponto e vírgula";Ana Souza;ana@exemplo.com;;;;;2,50;enviado;Visita'
    ]
    assert client.get("/exports/entries.csv", headers=ana).status_code == 403


# ---------- filtro por período ----------


def test_filtro_por_periodo(client):
    gestor = login(client, "gestor@exemplo.com")
    ana = login(client, "ana@exemplo.com")
    pid = client.post("/projects", headers=gestor, json={"code": "PER-1", "client": "C", "budget_hours": 100}).json()["id"]
    for day, hours in (("2020-01-10", 2), ("2020-01-31", 3), ("2020-02-01", 5)):
        client.post("/entries", headers=ana, json={"project_id": pid, "work_date": day, "hours": hours})
    jan = "date_from=2020-01-01&date_to=2020-01-31"

    mine = client.get(f"/entries?{jan}", headers=ana).json()
    assert sorted(e["hours"] for e in mine) == [2, 3]  # datas inclusivas
    assert [e["hours"] for e in client.get("/entries?date_from=2020-02-01&date_to=2020-02-29", headers=ana).json()] == [5]
    # gestor vê todos no período; técnico continua vendo só os seus
    assert len(client.get(f"/entries?all_users=true&{jan}", headers=gestor).json()) == 2

    proj = next(p for p in client.get(f"/reports/by-project?{jan}", headers=gestor).json() if p["id"] == pid)
    assert proj["total_hours"] == 5  # no período
    assert proj["used_hours"] == 10  # saldo considera tudo
    assert proj["period_people"] == 1

    users = {u["name"]: u for u in client.get(f"/reports/by-user?{jan}", headers=gestor).json()}
    assert users["Ana Souza"]["total_hours"] == 5
    assert users["Bruno Lima"]["total_hours"] == 0  # aparece mesmo sem horas no período


# ---------- cronômetro ----------


class Clock:
    """Relógio controlado nos testes do cronômetro."""

    def __init__(self, monkeypatch):
        import datetime as dt

        from app import main

        self.now = dt.datetime(2026, 10, 29, 12, 0, tzinfo=dt.UTC)
        monkeypatch.setattr(main, "utcnow", lambda: self.now)

    def advance(self, **kwargs):
        import datetime as dt

        self.now += dt.timedelta(**kwargs)


def test_cronometro_inicia_mostra_e_vira_lancamento(client, monkeypatch):
    clock = Clock(monkeypatch)
    ana = login(client, "ana@exemplo.com")
    pid = client.get("/projects", headers=ana).json()[0]["id"]
    assert client.get("/timer", headers=ana).json() is None

    r = client.post("/timer", headers=ana, json={"project_id": pid, "description": "Montagem"})
    assert r.status_code == 201 and r.json()["elapsed_seconds"] == 0
    assert client.post("/timer", headers=ana, json={"project_id": pid}).status_code == 409  # só um por vez

    clock.advance(hours=1, minutes=30, seconds=20)
    t = client.get("/timer", headers=ana).json()
    assert (t["project_id"], t["description"], t["elapsed_seconds"]) == (pid, "Montagem", 5420)

    r = client.post("/timer/stop", headers=ana, json={"work_date": "2026-10-29"})
    assert r.status_code == 201 and r.json()["hours"] == 1.51
    entry = next(e for e in client.get("/entries?all_users=false", headers=ana).json() if e["id"] == r.json()["id"])
    assert (entry["hours"], entry["work_date"], entry["description"]) == (1.51, "2026-10-29", "Montagem")
    assert client.get("/timer", headers=ana).json() is None


def test_cronometro_de_cada_usuario_e_separado(client, monkeypatch):
    Clock(monkeypatch)
    ana, bruno = login(client, "ana@exemplo.com"), login(client, "bruno@exemplo.com")
    pid = client.get("/projects", headers=ana).json()[0]["id"]
    client.post("/timer", headers=ana, json={"project_id": pid})
    assert client.get("/timer", headers=bruno).json() is None
    assert client.post("/timer", headers=bruno, json={"project_id": pid}).status_code == 201


def test_cronometro_limites_e_descartar(client, monkeypatch):
    clock = Clock(monkeypatch)
    gestor, ana = login(client, "gestor@exemplo.com"), login(client, "ana@exemplo.com")
    pid = client.get("/projects", headers=ana).json()[0]["id"]
    assert client.post("/timer/stop", headers=ana, json={"work_date": "2026-10-29"}).status_code == 404

    client.post("/timer", headers=ana, json={"project_id": pid})
    clock.advance(seconds=30)
    assert client.post("/timer/stop", headers=ana, json={"work_date": "2026-10-29"}).status_code == 422  # < 1 min
    clock.advance(hours=25)
    assert client.post("/timer/stop", headers=ana, json={"work_date": "2026-10-29"}).status_code == 422  # > 24 h
    assert client.delete("/timer", headers=ana).status_code == 204
    assert client.get("/timer", headers=ana).json() is None

    # Projeto inativo: não inicia
    client.patch(f"/projects/{pid}", headers=gestor, json={"active": False})
    assert client.post("/timer", headers=ana, json={"project_id": pid}).status_code == 422



# ---------- v0.6: apontamento com atividade, horários e status ----------


def activity_id(client, headers, name="Comissionamento"):
    return next(a["id"] for a in client.get("/activities", headers=headers).json() if a["name"] == name)


def test_atividades_padrao_e_gestao(client):
    gestor, ana = login(client, "gestor@exemplo.com"), login(client, "ana@exemplo.com")
    names = [a["name"] for a in client.get("/activities", headers=ana).json()]
    assert {"Projeto mecânico", "Integração de apertadeiras", "Comissionamento", "Calibração", "Outros"} <= set(names)

    assert client.post("/activities", headers=ana, json={"name": "X"}).status_code == 403
    new = client.post("/activities", headers=gestor, json={"name": "Validação de torque"}).json()["id"]
    assert client.post("/activities", headers=gestor, json={"name": "Validação de torque"}).status_code == 409
    client.patch(f"/activities/{new}", headers=gestor, json={"active": False})
    assert "Validação de torque" not in [a["name"] for a in client.get("/activities", headers=ana).json()]
    all_ = client.get("/activities?include_inactive=true", headers=gestor).json()
    assert any(a["name"] == "Validação de torque" and not a["active"] for a in all_)


def test_apontamento_com_inicio_fim_e_intervalo(client):
    ana = login(client, "ana@exemplo.com")
    pid = client.get("/projects", headers=ana).json()[0]["id"]
    aid = activity_id(client, ana)
    body = {"project_id": pid, "activity_id": aid, "work_date": "2026-10-29",
            "start_time": "08:00", "end_time": "12:30", "break_minutes": 15, "description": "Montagem"}
    r = client.post("/entries", headers=ana, json=body)
    assert r.status_code == 201 and r.json()["hours"] == 4.25
    e = next(e for e in client.get("/entries", headers=ana).json() if e["id"] == r.json()["id"])
    assert (e["start_time"], e["end_time"], e["break_minutes"], e["hours"]) == ("08:00", "12:30", 15, 4.25)
    assert (e["activity_name"], e["status"]) == ("Comissionamento", "enviado")

    bad = [
        body | {"end_time": "07:00"},  # fim antes do início
        body | {"break_minutes": 300},  # intervalo maior que o período
        body | {"end_time": None},  # só um dos horários
        body | {"start_time": "8:00"},  # formato
        body | {"start_time": "24:00"},
        {k: v for k, v in body.items() if k not in ("start_time", "end_time")},  # sem horários e sem horas
    ]
    for b in bad:
        assert client.post("/entries", headers=ana, json=b).status_code == 422, b
    # Sem horários, vale o total de horas (lançamentos antigos / integrações)
    legacy = {"project_id": pid, "work_date": "2026-10-29", "hours": 2}
    assert client.post("/entries", headers=ana, json=legacy).status_code == 201


def test_filtros_do_historico(client):
    gestor, ana, bruno = (login(client, e) for e in ("gestor@exemplo.com", "ana@exemplo.com", "bruno@exemplo.com"))
    p1 = client.post("/projects", headers=gestor, json={"code": "HIS-1", "client": "A"}).json()["id"]
    p2 = client.post("/projects", headers=gestor, json={"code": "HIS-2", "client": "B"}).json()["id"]
    cal = activity_id(client, ana, "Calibração")
    base = {"work_date": "2019-05-10", "start_time": "08:00", "end_time": "09:00"}
    client.post("/entries", headers=ana, json=base | {"project_id": p1, "activity_id": cal})
    client.post("/entries", headers=ana, json=base | {"project_id": p2})
    client.post("/entries", headers=bruno, json=base | {"project_id": p1})
    q = "date_from=2019-05-01&date_to=2019-05-31"

    assert len(client.get(f"/entries?{q}", headers=ana).json()) == 2
    assert len(client.get(f"/entries?{q}&project_id={p1}", headers=ana).json()) == 1
    assert len(client.get(f"/entries?{q}&activity_id={cal}", headers=ana).json()) == 1
    assert len(client.get(f"/entries?{q}&status=enviado", headers=ana).json()) == 2
    assert client.get(f"/entries?{q}&status=aprovado", headers=ana).json() == []
    assert client.get(f"/entries?{q}&status=xyz", headers=ana).status_code == 422
    # Gestor: todos, ou de uma pessoa; técnico não consegue ver de outro com user_id
    assert len(client.get(f"/entries?{q}&all_users=true", headers=gestor).json()) == 3
    bruno_id = client.get("/me", headers=bruno).json()["id"]
    assert len(client.get(f"/entries?{q}&user_id={bruno_id}", headers=gestor).json()) == 1
    assert len(client.get(f"/entries?{q}&user_id={bruno_id}", headers=ana).json()) == 2  # ignora: só os dela


def test_apontamento_aprovado_fica_travado(client):
    from app.db import connect

    ana = login(client, "ana@exemplo.com")
    pid = client.get("/projects", headers=ana).json()[0]["id"]
    body = {"project_id": pid, "work_date": "2026-10-29", "hours": 1}
    eid = client.post("/entries", headers=ana, json=body).json()["id"]
    with connect() as conn:  # aprovação ainda não tem tela; simula direto no banco
        conn.execute("UPDATE entries SET status = 'aprovado' WHERE id = ?", (eid,))
    assert client.put(f"/entries/{eid}", headers=ana, json=body).status_code == 409
    assert client.delete(f"/entries/{eid}", headers=ana).status_code == 409


def test_preferencia_do_cronometro_por_pessoa(client):
    ana, bruno = login(client, "ana@exemplo.com"), login(client, "bruno@exemplo.com")
    assert client.get("/me", headers=ana).json()["use_timer"] is True
    assert client.patch("/me/preferences", headers=ana, json={"use_timer": False}).json()["use_timer"] is False
    assert client.get("/me", headers=ana).json()["use_timer"] is False
    assert client.get("/me", headers=bruno).json()["use_timer"] is True
    r = client.post("/auth/login", json={"email": "ana@exemplo.com", "password": "demo123"})
    assert r.json()["user"]["use_timer"] is False


def test_cronometro_guarda_atividade_e_horarios(client, monkeypatch):
    clock = Clock(monkeypatch)
    ana = login(client, "ana@exemplo.com")
    pid = client.get("/projects", headers=ana).json()[0]["id"]
    aid = activity_id(client, ana, "Programação (PLC/controlador)")
    t = client.post("/timer", headers=ana, json={"project_id": pid, "activity_id": aid}).json()
    assert t["activity_name"] == "Programação (PLC/controlador)"
    clock.advance(minutes=45)
    eid = client.post("/timer/stop", headers=ana,
                      json={"work_date": "2026-10-29", "start_time": "09:00", "end_time": "09:45"}).json()["id"]
    e = next(e for e in client.get("/entries", headers=ana).json() if e["id"] == eid)
    assert (e["activity_name"], e["start_time"], e["end_time"], e["hours"]) == ("Programação (PLC/controlador)", "09:00", "09:45", 0.75)


def test_dashboard(client):
    gestor, ana = login(client, "gestor@exemplo.com"), login(client, "ana@exemplo.com")
    pid = client.post("/projects", headers=gestor, json={"code": "DSH-1", "client": "C", "budget_hours": 10}).json()["id"]
    for day, start, end in (("2030-01-07", "08:00", "10:00"), ("2030-01-09", "08:00", "11:30"), ("2030-01-14", "08:00", "09:00")):
        client.post("/entries", headers=ana, json={"project_id": pid, "work_date": day, "start_time": start, "end_time": end})

    d = client.get("/dashboard?today=2030-01-09", headers=ana).json()  # quarta-feira
    assert d["today_hours"] == 3.5
    assert d["week_hours"] == 5.5  # segunda 07 a domingo 13
    assert [x["date"] for x in d["week_days"]][0] == "2030-01-07" and len(d["week_days"]) == 7
    assert d["month_hours"] == 5.5  # até "hoje"
    assert "DSH-1" in [p["code"] for p in d["projects_in_progress"]]
    assert d["recent_entries"][0]["work_date"] == "2030-01-14"
    assert d["team_week_hours"] is None
    assert client.get("/dashboard?today=2030-01-09", headers=gestor).json()["team_week_hours"] == 5.5


def test_relatorio_por_atividade(client):
    gestor, ana = login(client, "gestor@exemplo.com"), login(client, "ana@exemplo.com")
    pid = client.get("/projects", headers=ana).json()[0]["id"]
    cal = activity_id(client, ana, "Calibração")
    client.post("/entries", headers=ana, json={"project_id": pid, "activity_id": cal, "work_date": "2018-03-01", "hours": 3})
    client.post("/entries", headers=ana, json={"project_id": pid, "work_date": "2018-03-02", "hours": 1})
    rows = {r["name"]: r["total_hours"] for r in client.get(
        "/reports/by-activity?date_from=2018-03-01&date_to=2018-03-31", headers=gestor).json()}
    assert rows == {"Calibração": 3, "Sem atividade": 1}
    assert client.get("/reports/by-activity", headers=ana).status_code == 403



def test_lista_de_atividades_v2_entra_uma_vez_sem_apagar(tmp_path, monkeypatch):
    """Banco que já tinha a lista antiga: ganha as atividades novas uma vez; renomeadas não voltam."""
    from app import db

    if db.database_url():
        pytest.skip("teste só para SQLite")
    monkeypatch.setenv("TIMESHEET_DB", str(tmp_path / "v06.db"))
    db.init_db()
    with db.connect() as conn:  # simula o estado da v0.6: lista antiga, sem controle de versão
        conn.execute("DELETE FROM activities")
        conn.execute("DELETE FROM app_meta")
        for name in ("Instalação", "Manutenção", "Calibração", "Reunião"):
            conn.execute("INSERT INTO activities (name) VALUES (?)", (name,))
    db.init_db()
    with db.connect() as conn:
        names = {r["name"] for r in conn.execute("SELECT name FROM activities")}
        assert {"Instalação", "Manutenção", "Projeto mecânico", "Integração de apertadeiras"} <= names
        assert sum(1 for n in names if n == "Calibração") == 1  # não duplica
        conn.execute("UPDATE activities SET name = 'Projeto mecânico (CAD)' WHERE name = 'Projeto mecânico'")
    db.init_db()
    with db.connect() as conn:
        names = {r["name"] for r in conn.execute("SELECT name FROM activities")}
    assert "Projeto mecânico" not in names and "Projeto mecânico (CAD)" in names
