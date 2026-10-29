# Timesheet

App web para registrar e somar as horas que uma equipe técnica gasta em cada projeto.
Técnicos lançam horas; gestores veem os totais por projeto e por funcionário.

> Projeto de portfólio. Todos os dados de exemplo são **fictícios**. A ideia é que ele possa
> virar uma ferramenta interna depois (veja [Próximos passos](#próximos-passos)).

## Requisitos levantados

| Tema | Decisão |
|---|---|
| Usuários | Técnicos/engenheiros e gestor, até ~20 pessoas |
| Plataforma | Web responsiva (PC e navegador do celular) |
| Lançamento | Manual: projeto, data, horas e descrição |
| Relatórios | Total por projeto e total por funcionário |
| Acesso | Login com e-mail e senha; sem aprovação de horas |
| Uso | Portfólio agora, pensado para uso interno depois |

## MVP (v0.1)

- Login com e-mail e senha, dois papéis: **técnico** e **gestor**
- Técnico: lança horas e edita/apaga os próprios lançamentos
- Gestor: tudo do técnico, mais
  - relatórios de total de horas **por projeto** e **por funcionário**
  - cadastro de projetos (criar, ativar/desativar)
  - cadastro de usuários
- Projeto desativado não aceita novos lançamentos, mas mantém o histórico
- Layout com menu lateral no PC e barra inferior no celular

**Fora do MVP:** aprovação de horas, cronômetro, filtro por período, exportação Excel/SAP, modo offline.

## Stack

| Camada | Tecnologia | Por quê |
|---|---|---|
| Front-end | Flutter Web (Dart) | Reaproveita a experiência com Flutter; dá para gerar app mobile depois |
| API | Python + FastAPI | Simples, tipada, documentação automática em `/docs` |
| Banco | SQLite | Zero configuração local; SQL direto, fácil de migrar para Postgres |
| Auth | Senha com PBKDF2 + token opaco | Só biblioteca padrão, sem serviço externo |
| Testes | pytest (API) e flutter test (app) | |

```
timesheet/
├── backend/          API FastAPI + SQLite
│   ├── app/          main.py (rotas), db.py, security.py, seed.py
│   └── tests/
└── app/              Flutter Web
    └── lib/          main.dart, api.dart, models.dart, pages/
```

## Como rodar localmente

Pré-requisitos: Python 3.11+ e Flutter 3.x com Chrome.

### 1. API

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt -r requirements-dev.txt
.venv/bin/python -m app.seed          # cria timesheet.db com dados fictícios
.venv/bin/uvicorn app.main:app --reload --port 8000
```

A documentação interativa da API fica em <http://localhost:8000/docs>.

### 2. App

Em outro terminal:

```bash
cd app
flutter pub get
flutter run -d chrome
```

O app procura a API em `http://localhost:8000`. Para outro endereço:
`flutter run -d chrome --dart-define=API_URL=http://outro-host:8000`.

### Usuários de demonstração

Senha de todos: `demo123`

| E-mail | Papel |
|---|---|
| `gestor@exemplo.com` | gestor |
| `ana@exemplo.com` | técnico |
| `bruno@exemplo.com` | técnico |
| `carla@exemplo.com` | técnico |

Para recomeçar do zero, apague `backend/timesheet.db` e rode o seed de novo.

## Testes

```bash
cd backend && .venv/bin/pytest
cd app && flutter test
```

## Deploy (versão de teste online)

> **Só dados fictícios.** Colocar dados reais da Atlas Copco num servidor externo precisa do aval do TI da empresa.

| Parte | Onde | Plano |
|---|---|---|
| Front (Flutter Web) | GitHub Pages: <https://ocarloshenriqueb.github.io/timesheet/> | grátis |
| API (FastAPI) | Render, serviço `timesheet-api` | free: dorme após ~15 min parado, o 1º acesso demora até 1 min |
| Banco | Neon Postgres | free, persistente |

**Por que Postgres e não SQLite online:** o disco do plano grátis do Render é apagado a cada deploy
ou reinício, então o arquivo `timesheet.db` sumiria. A API usa SQLite quando `DATABASE_URL` não existe
(desenvolvimento) e Postgres quando existe (produção), com o mesmo SQL.

### Variáveis de ambiente da API

| Variável | Para quê |
|---|---|
| `DATABASE_URL` | String de conexão do Neon (`postgresql://…?sslmode=require`) |
| `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `ADMIN_NAME` | Primeiro gestor, criado só se o banco estiver vazio. Depois ele cadastra os colegas pela tela **Cadastros** |
| `CORS_ORIGINS` | Domínios do front que podem chamar a API, separados por vírgula (`https://ocarloshenriqueb.github.io`). Sem ela, só o localhost |
| `SEED_PASSWORD` | Só para rodar `python -m app.seed` contra um banco remoto; o seed recusa usar a senha padrão `demo123` fora do local |

Senhas e a URL do banco ficam só no painel do Render, nunca no repositório. Não há segredo de JWT:
a API usa tokens aleatórios guardados no banco.

### Passo a passo (uma vez)

1. **Neon** (<https://neon.tech>, entrar com GitHub): criar um projeto e copiar a *connection string*.
2. **Render** (<https://render.com>, entrar com GitHub): *New → Blueprint*, escolher este repositório.
   O [render.yaml](render.yaml) cria o serviço; preencher `DATABASE_URL`, `ADMIN_EMAIL` e `ADMIN_PASSWORD`.
3. Conferir que <https://timesheet-api.onrender.com/health> responde `{"ok": true}`.
4. **GitHub**: em *Settings → Secrets and variables → Actions → Variables*, criar `API_URL` com a URL do Render
   e, em *Settings → Pages*, usar *Source: GitHub Actions*.
5. Rodar o workflow [Deploy front](.github/workflows/pages.yml) (*Actions → Run workflow*). Ele também roda
   sozinho a cada push que mexa em `app/`. A API é publicada de novo pelo Render a cada push na `main`.

### Testar o modo Postgres localmente

Com qualquer Postgres de teste (o banco é apagado a cada teste):

```bash
cd backend && DATABASE_URL=postgresql://... .venv/bin/pytest
```

## API

| Método | Rota | Quem |
|---|---|---|
| POST | `/auth/login`, `/auth/logout` | todos |
| GET | `/me` | logado |
| GET | `/projects` | logado |
| POST / PATCH | `/projects`, `/projects/{id}` | gestor |
| GET / POST | `/users` | gestor |
| GET / POST | `/entries` (`?all_users=true` para gestor) | logado |
| PUT / DELETE | `/entries/{id}` | dono ou gestor |
| GET | `/reports/by-project`, `/reports/by-user` | gestor |

## Próximos passos

1. Filtro por período (semana/mês) nos lançamentos e relatórios
2. Exportar CSV/Excel
3. Aprovação de horas pelo gestor
4. Cronômetro por projeto
5. Para uso interno de verdade: expiração de token, troca de senha,
   hospedagem aprovada pela TI e política de dados (LGPD)
