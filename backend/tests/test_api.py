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
            conn.execute("DROP TABLE IF EXISTS tokens, entries, projects, users")
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
    old.commit()
    old.close()

    monkeypatch.setenv("TIMESHEET_DB", str(path))
    db.init_db()
    db.init_db()  # rodar duas vezes não pode falhar
    with db.connect() as conn:
        row = dict(conn.execute("SELECT * FROM projects").fetchone())
    assert row["client"] == "" and row["budget_hours"] is None and row["due_date"] is None
