# Manual do Timesheet

O Timesheet registra as horas de cada projetista em cada projeto e mostra ao gestor, por cores, quem está dentro das horas e do prazo. Este manual explica cada tela para os dois perfis: projetista e gestor.

## 1. Acesso

O Timesheet abre no navegador, sem instalar nada: [ocarloshenriqueb.github.io/timesheet](https://ocarloshenriqueb.github.io/timesheet/). Funciona melhor no computador.

1. Abra o link e entre com o e-mail e a senha que o gestor cadastrou para você.
2. No primeiro acesso do dia, a entrada pode levar até 1 minuto: o servidor de testes "acorda" quando fica parado.
3. O menu lateral, à esquerda, leva a todas as telas. Seu nome e perfil aparecem no canto inferior esquerdo.
4. O item **Ajuda** no menu abre este manual dentro do próprio Timesheet.

| Perfil | O que pode fazer |
| --- | --- |
| Projetista | Lançar e corrigir as próprias horas, consultar o próprio histórico e os projetos em que está |
| Gestor | Tudo do projetista, mais: projetos e equipes, relatórios, acompanhamento da equipe, usuários e atividades |

**Menu da conta** (clique no seu nome, no canto inferior esquerdo):

- **Usar cronômetro**: liga ou desliga o cronômetro na tela de Apontamento. Cada pessoa escolhe o seu.
- **Sair**: encerra a sessão. Use em computadores compartilhados.

Esqueceu a senha? Peça ao gestor para redefini-la em Gestão → Usuários. Ainda não há troca de senha pelo próprio usuário.

## 2. Para o projetista

### Dashboard

A tela inicial mostra suas horas de hoje, da semana (segunda a domingo) e do mês, um gráfico da semana, os projetos em andamento com a cor de alerta e seus últimos apontamentos. O botão **Novo apontamento** leva direto para o lançamento.

### Apontamento: lançar horas

1. Abra **Apontamento** no menu.
2. Escolha o **Projeto**. Só aparecem os projetos em que você está na equipe e os abertos a todos.
3. Escolha a **Atividade** (ex.: Projeto mecânico, Integração de apertadeiras, Comissionamento).
4. Confira a **Data** (vem com hoje; clique para mudar).
5. Informe **Início** e **Fim**. Pode digitar só números: "8" vira 08:00 e "1730" vira 17:30. O relógio ao lado abre um seletor.
6. Informe o **Intervalo** em minutos (almoço, pausa). O **Total** aparece na hora.
7. Descreva o trabalho e clique em **Registrar** (ou aperte Enter).

Depois de registrar, o próximo apontamento já começa no horário em que o anterior terminou, com o mesmo projeto e atividade. À direita (ou abaixo), a lista **Hoje** mostra o que já foi lançado no dia.

Se o fim ficar antes do início, ou o intervalo for maior que o período, o total fica em vermelho e o botão não registra. Um turno que passa da meia-noite é lançado em dois apontamentos.

### Cronômetro (opcional)

Aparece no topo do Apontamento para quem deixou **Usar cronômetro** ligado no menu da conta.

1. Escolha projeto e atividade e clique em **Iniciar**.
2. Ele continua contando mesmo se você fechar o navegador ou abrir em outro computador.
3. Ao terminar, clique em **Parar e lançar**: vira um apontamento com início, fim e as horas contadas.
4. **X (Descartar)** apaga o cronômetro sem lançar.

Menos de 1 minuto não é lançado. Acima de 24 horas também não: provavelmente ficou ligado por engano; descarte e lance à mão.

### Histórico

Tabela com todos os seus apontamentos. Use os filtros de **período** (esta semana, este mês, mês passado, últimos 30 dias, tudo ou datas escolhidas), **projeto** e **status**.

- **Editar**: corrige projeto, atividade, data, horários e descrição.
- **Apagar**: remove o apontamento, depois de confirmar.
- Apontamento com status **Aprovado** fica travado: só o gestor altera.

### Projetos

Consulta dos projetos que você pode ver: número, cliente, horas estimadas e realizadas, saldo e data de entrega, com as cores de alerta. O projetista só consulta; quem cria e edita é o gestor.

## 3. Para o gestor

O gestor vê no menu, além das telas do projetista, a seção **Gestão** com Relatórios e Gestão. No Dashboard aparece também a grade de acompanhamento da equipe.

### Projetos: criar e editar

1. Em **Projetos**, clique em **Novo projeto**.
2. Preencha **Projeto (número)** e **Cliente**. Se o projeto estiver no catálogo do SAP, clique no ícone de nuvem ao lado do número: cliente, horas, entrega, elemento PEP e ordem de venda são preenchidos sozinhos.
3. Informe **Horas previstas** e **Data de entrega** (opcionais) e salve.

Na tabela, o lápis edita (o número não muda) e a chave ativa ou desativa. Projeto inativo não aceita novos lançamentos, mas mantém o histórico. Use a busca e o filtro Ativos / Inativos / Todos para achar projetos.

### Equipe do projeto

1. Na coluna **Equipe**, clique em "Aberto a todos" ou "N pessoa(s)".
2. Em **Alocar projetista**, escolha quem fica com o projeto.
3. Para cada pessoa, informe as **horas previstas** dela e o **prazo** dela. Prazo vazio usa a entrega do projeto.
4. Clique em **Salvar equipe**.

Projeto com equipe só aceita horas dos alocados. Projeto sem ninguém alocado fica aberto a todos (útil para atividades internas, como treinamento). O ponto colorido ao lado de cada pessoa mostra a situação dela hoje.

### Catálogo SAP

Em **Projetos → Catálogo SAP**, cole a lista de projetos exportada do SAP para o Excel, com o cabeçalho. Colunas: projeto; cliente; pep; ordem_venda; horas_previstas; data_entrega (obrigatórias: projeto e cliente). Depois disso, o ícone de nuvem no cadastro preenche os dados.

### Relatórios

Horas **por projeto**, **por atividade** e **por funcionário** no período escolhido, com gráfico e tabela. **Exportar CSV** baixa os apontamentos do período num arquivo que abre no Excel, em formato próximo ao apontamento de horas do SAP (CATS).

### Gestão

**Acompanhamento da equipe**: a grade com cada colaborador, os projetos dele e as horas de cada dia. A cor de cada dia mostra a situação daquela pessoa naquele projeto até aquele dia (veja a seção 4). No fim da linha: total, previsto, prazo e a situação de hoje; passe o mouse para ver o saldo e os dias até o prazo. Troque entre semana e mês no seletor de período.

**Usuários**:

- **Novo usuário**: nome, e-mail, senha inicial e perfil.
- **Editar** (lápis): muda nome, e-mail e perfil e redefine a senha. Senha vazia mantém a atual.
- **Excluir** (ícone vermelho): quem nunca lançou horas é apagado; quem já lançou fica desativado, sem acesso, mas com as horas preservadas. Pode ser reativado.
- O gestor não exclui a si mesmo, e o sistema sempre mantém pelo menos um gestor ativo.

**Atividades**: a lista usada no apontamento. Crie, renomeie ou desative as que não usar.

### Histórico da equipe

No **Histórico**, o filtro **Pessoa** mostra os seus apontamentos, os de toda a equipe ou os de uma pessoa. O gestor pode corrigir qualquer apontamento, inclusive os aprovados.

## 4. O que as cores significam

A mesma regra vale para os projetos, a grade da equipe e o Dashboard. Horas: quanto das horas previstas já foi usado. Prazo: quantos dias faltam para a entrega. Quando as duas indicam cores diferentes, vale a pior.

| Cor | Horas usadas do previsto | Prazo |
| --- | --- | --- |
| Verde | Até 70% | Faltam mais de 7 dias |
| Amarelo | De 70% a 90% | Faltam 7 dias ou menos (inclui o dia da entrega) |
| Vermelho | Acima de 90% | Entrega atrasada |
| Roxo | Passou de 100% ("Estourado em X h") | — |
| Cinza | Sem horas previstas | Sem prazo |

Na grade da equipe, cada dia conta as horas acumuladas daquela pessoa naquele projeto até aquele dia, contra as horas e o prazo dela. Assim, a cor mostra em que dia a pessoa entrou na faixa de atenção.

## 5. Dúvidas comuns

| Situação | O que fazer |
| --- | --- |
| A entrada demora | Normal no primeiro acesso do dia: espere até 1 minuto |
| "Não foi possível falar com a API" | Aguarde um pouco e tente de novo; se continuar, avise o gestor |
| O projeto não aparece no Apontamento | Você não está na equipe dele, ou ele está inativo: peça ao gestor |
| "Você não está alocado neste projeto" | O projeto tem equipe definida e você não está nela: peça ao gestor |
| O botão Registrar não funciona | Confira projeto, atividade e horários; o fim precisa ser depois do início |
| Esqueci a senha | O gestor redefine em Gestão → Usuários |
| Lancei errado | Corrija ou apague no Histórico; se estiver Aprovado, peça ao gestor |
| O cronômetro sumiu | Ligue Usar cronômetro no menu da conta, no canto inferior esquerdo |
| Usuário excluído não entra mais | Está desativado; o gestor pode reativar em Gestão → Usuários |

Esta é uma versão de teste, com dados fictícios. Dados reais da empresa só depois do aval do TI. A aprovação de horas pelo gestor e a conexão direta com o SAP ainda estão em desenvolvimento.
