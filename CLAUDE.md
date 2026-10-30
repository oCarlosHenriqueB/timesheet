# Timesheet — contexto para o Claude

Lido automaticamente em toda sessão nova nesta pasta. O README explica o produto; aqui ficam as decisões,
as convenções e as pendências que não estão no código.

## Quem e para quê

- Dono: Carlos (GitHub oCarlosHenriqueB). Conversa em **português**; explicações simples, passo a passo.
- Trabalha na Atlas Copco, área de **apertadeiras e automação industrial**. O app controla horas da equipe de
  **projetistas** por projeto; clientes do segmento são montadoras, máquinas agrícolas, equipamentos pesados.
- Fase: protótipo para mostrar ao gestor/cliente. **Só dados fictícios** até o TI aprovar hospedagem e dados reais.

## Stack e onde roda

| Parte | Tecnologia | Online |
|---|---|---|
| App | Flutter Web (Dart), `app/` | GitHub Pages: https://ocarloshenriqueb.github.io/timesheet/ (workflow `.github/workflows/pages.yml`, variável de repo `API_URL`) |
| API | Python + FastAPI, `backend/` | Render, serviço `timesheet-api`: https://timesheet-api-xp0u.onrender.com (auto-deploy de `backend/` na `main`; plano free dorme ~15 min) |
| Banco | SQLite local / PostgreSQL online (mesmo SQL, `app/db.py` troca `?`→`%s`) | Neon (Ohio). Env no Render: `DATABASE_URL`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `ADMIN_NAME`, `CORS_ORIGINS`, `PYTHON_VERSION` |

Push na `main` publica tudo. Depois de publicar, conferir: `gh run list -R oCarlosHenriqueB/timesheet -L 1`
e `curl https://timesheet-api-xp0u.onrender.com/openapi.json` (rota nova aparece quando o Render terminou).

## Rodar e testar

```bash
cd backend && .venv/bin/python -m app.seed      # banco local com dados fictícios (senha demo123)
cd backend && .venv/bin/uvicorn app.main:app --reload --port 8000
cd app && flutter run -d chrome                  # ou flutter build web + servir app/build/web
cd backend && .venv/bin/pytest                   # 37 testes
cd app && flutter analyze && flutter test        # 34 testes
```

- Testes da API também no Postgres: `DATABASE_URL=postgresql://... .venv/bin/pytest` (apaga as tabelas: só banco de teste).
  Sem Postgres local: o pacote `pgserver` funciona com Python 3.11 (não com 3.14).
- **Não usar `dart format`**: o `dart` do PATH é 3.0.2 (Homebrew), antigo, quebra a sintaxe nova e reformata tudo.
  O estilo do projeto é linhas de até ~120 colunas, sem formatador automático.
- No navegador de testes, o Flutter Web às vezes guarda a versão antiga em cache: abrir por `127.0.0.1:8080`
  em vez de `localhost:8080`, ou forçar recarga.

## Organização do código

- `backend/app/main.py` rotas; `db.py` esquema + migrações (`MIGRATIONS`, só ADD COLUMN, nunca apagam dados;
  `_seed_activities` acrescenta atividades padrão uma vez por `ACTIVITIES_VERSION`); `sap.py` integração SAP;
  `seed.py` dados fictícios.
- `app/lib/screens/` uma tela por arquivo + `shell.dart` (menu lateral); `widgets/` componentes reutilizáveis;
  `dialogs/` janelas; `api.dart` todas as chamadas; `models.dart`; `budget.dart` regras de cor; `period.dart`.
- Regra: **toda regra de negócio fica na API**; o app só calcula o que mostra enquanto a pessoa digita.
- Manual de uso: `app/assets/MANUAL.md`, exibido na tela **Ajuda** (projetista não vê a seção 3, do gestor).
  Mudou funcionalidade visível → atualizar o manual e a seção do README.

## Decisões já tomadas (não reabrir sem o Carlos pedir)

- Perfis: gestor e projetista. Na API o papel do projetista chama `tecnico`; nas telas, **"Projetista"**.
- Apontamento por **início, fim e intervalo** (horas calculadas na API); lançamentos antigos só com total.
  Status: rascunho/enviado/aprovado/rejeitado; tudo nasce `enviado`; aprovado trava para o projetista.
- Cronômetro opcional por pessoa (`use_timer`, menu da conta), guardado no servidor, 1 por pessoa, 1 min–24 h.
- Cores: horas usadas ≤70% verde, 70–90% amarelo, >90% vermelho, >100% roxo; prazo ≤7 dias amarelo,
  atrasado vermelho; vale a pior. Grade da equipe colore cada dia pelo acumulado da pessoa no projeto.
- Equipe do projeto: projeto com membros só aceita horas deles; sem membros = aberto a todos.
  Cada membro tem horas previstas e prazo próprios (prazo vazio = entrega do projeto).
- Excluir usuário: sem horas → apaga; com horas → desativa (histórico preservado). Nunca sem gestor ativo.
- Ao criar usuário/redefinir senha, o app mostra os dados de acesso para copiar (evita senha digitada errado).
- **Clientes reais (Caterpillar, John Deere, VW...) nunca no repositório público**: demo usa nomes fictícios.
  Sem logo/marca oficial da Atlas Copco (espaço reservado no menu e no login).
- Transparência: o desenvolvimento foi assistido por IA (Claude Code); a apresentação técnica diz isso.

## Pendências

- [ ] **Carlos: trocar a senha do banco no Neon** (Reset password do `neondb_owner`) e atualizar `DATABASE_URL`
      no Render — a string antiga apareceu numa conversa.
- [ ] Aprovação de horas pelo gestor (status já existe; falta a tela em Gestão).
- [ ] Conexão direta com SAP (`SAP_PROVIDER=odata` responde 501; depende do TI: perguntas no README).
- [ ] Para uso real: troca de senha pelo próprio usuário, expiração de sessão, hospedagem interna, LGPD.
- [ ] README do perfil GitHub (repo oCarlosHenriqueB/oCarlosHenriqueB) ainda mostra o Orbis como projeto atual.

## Materiais fora do repositório (conta Claude do Carlos)

- Apresentação comercial: https://claude.ai/artifact/GxiSfrPDs1SpRyVdsPPC6N
- Apresentação técnica "Como o Timesheet foi construído": https://claude.ai/artifact/Xwf9vbB6PcAqsDkBL4cAr4
- Manual editável (cópia antiga; a versão oficial é `app/assets/MANUAL.md`): https://claude.ai/artifact/W4q5AK4GKM51Gh8YsNitTE
