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
            conn.execute("DROP TABLE IF EXISTS tokens, entries, projects, users, sap_catalog")
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
    assert {e["user_name"] for e in entries} == {"Ana Técnica"}
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
        "code": "PRJ-005", "client": "Laboratório Exemplo E", "sap_wbs": "BR-PRJ-005-01",
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
    assert lines[0] == "data;projeto;pep;ordem_venda;cliente;funcionario;email;horas;descricao"
    assert lines[1:] == ['15.01.2020;EXP-1;BR-EXP;;"Cliente; com ponto e vírgula";Ana Técnica;ana@exemplo.com;2,50;Visita']
    assert client.get("/exports/entries.csv", headers=ana).status_code == 403
