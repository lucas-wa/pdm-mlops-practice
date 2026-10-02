# 00 — Pré-requisitos e camada gold

Este documento é a preparação **anterior à aula**. Ele cobre duas coisas: o **checklist de ambiente** (o que precisa estar pronto no GCP) e o **contrato de dados** (o que exatamente será lido da gold, o que é alvo, o que é feature e o que precisa ser excluído).

> **Antes de qualquer coisa:** leia o [`README.md`](README.md) e o aviso de consumo de créditos. O encerramento em [`05-encerramento-custos.md`](05-encerramento-custos.md) é parte obrigatória da atividade.

---

## 1. Checklist de pré-requisitos

### 1.1 Conta e projeto

- [ ] Projeto GCP próprio, com **ID anotado** (usado como `SEU_PROJECT_ID` em todos os comandos).
- [ ] **Faturamento (billing) ativo** no projeto, vinculado aos **créditos educacionais** da disciplina. Sem billing, a API do Vertex AI não habilita.
- [ ] Conta de faturamento identificada (`SEU_BILLING_ACCOUNT_ID`) — necessária para configurar o budget no encerramento.
- [ ] **Budget com alerta configurado** antes de criar qualquer recurso, para acompanhar o consumo dos créditos. Ver [`05-encerramento-custos.md`](05-encerramento-custos.md), seção de Budgets.

### 1.2 Permissões

- [ ] Você é **`Owner`** do seu próprio projeto (`roles/owner`), então **já tem todas as permissões necessárias — não precisa conceder nada**.

A tabela abaixo é **apenas referência para o cenário de projeto compartilhado** (ou de uma conta de serviço dedicada), onde não existe `roles/owner` e os papéis mínimos precisam ser concedidos um a um:

| Papel | Para quê |
|---|---|
| `roles/aiplatform.user` | Criar runs no Experiments, registrar modelo, criar endpoint, predizer |
| `roles/storage.objectAdmin` | Gravar e ler `model.joblib` no bucket da aula |
| `roles/bigquery.dataViewer` | Ler a tabela gold |
| `roles/bigquery.jobUser` | Executar as consultas |

Os comandos de concessão desse cenário estão em [`01-setup-gcp.md`](01-setup-gcp.md) e em [`scripts/00_setup.sh`](scripts/00_setup.sh).

### 1.3 APIs habilitadas

- [ ] `aiplatform.googleapis.com` (obrigatória)
- [ ] `storage.googleapis.com`
- [ ] `bigquery.googleapis.com`
- [ ] `compute.googleapis.com` (necessária para os nós do endpoint)

Passo a passo em [`01-setup-gcp.md`](01-setup-gcp.md).

### 1.4 Recursos

- [ ] Dataset **`aula_pdm`** existente em **`us-central1`**, com a tabela gold populada.
- [ ] Bucket da aula **`${PROJECT_ID}-mlops-aula`** criado em `us-central1`.
- [ ] Bucket compartilhado **`${PROJECT_ID}-aula-pdm`** preservado — **não mexer**, é infraestrutura das aulas anteriores.

> **Região.** Dataset, bucket, experimento, modelo e endpoint devem estar todos em **`us-central1`**. Recursos do Vertex AI não leem datasets do BigQuery de outra região sem cópia intermediária.

### 1.5 Ambiente de execução

- [ ] Acesso ao **BigQuery Studio** no console (o runtime por baixo é o Colab Enterprise).
- [ ] Notebook [`notebooks/treino_experiments_registry.ipynb`](notebooks/treino_experiments_registry.ipynb) aberto e com a primeira célula de instalação executada.

> **O runtime consome créditos enquanto estiver ativo.** Há desligamento automático por inatividade (aproximadamente 180 minutos), mas apagar o runtime ao final é o que garante o encerramento. Ver [`05-encerramento-custos.md`](05-encerramento-custos.md).

### 1.6 A confirmar ao vivo, antes da aula

Itens sensíveis a versão e a mudanças de interface:

- [ ] **Nome exato da tabela gold** e colunas disponíveis nesta turma (o schema não é fixo — a gold foi construída pelos alunos).
- [ ] **Rótulos do console**: a documentação aparece como "Gemini Enterprise Agent Platform", mas o console ainda exibe **"Vertex AI"**. Confirmar onde estão Experiments, Model Registry e Online prediction.
- [ ] **Tag do container de serving** scikit-learn, casando com a versão do `scikit-learn` usada no treino (ver [`03-model-registry.md`](03-model-registry.md)).
- [ ] **Tempo de provisionamento do endpoint** no projeto de ensaio, para dimensionar o roteiro.

---

## 2. Contrato de dados

O contrato abaixo vale para o notebook, para o modelo registrado e para o payload do endpoint. Ele vem do planejamento da disciplina (`docs/planejamento-aulas-mlops-gcp.md`) e não deve ser alterado durante a aula.

| Item | Definição |
|---|---|
| Pergunta | Quanto seria o **preço anunciado** de um imóvel com determinadas características? |
| Alvo | **`preco`** — preço **de anúncio**, não preço efetivo de venda |
| Entradas candidatas | `area_util`, `area_total`, `quartos`, `banheiros`, `garagens`, `bairro`, `cidade`, conforme disponibilidade na gold |
| Recorte | Imóveis à venda; preferencialmente **uma cidade** e **um segmento** com exemplos suficientes |
| Modelo | `RandomForestRegressor` pequeno (scikit-learn), dentro de um `Pipeline` |
| Baseline | Previsão constante igual à **mediana do `preco` do conjunto de treino** |
| Avaliação | **MAE em reais**; validação para seleção, teste separado para avaliação final |
| Inferência | Endpoint HTTP que recebe as features e devolve preço estimado |

> **O alvo é preço de anúncio.** Isso muda a interpretação do erro: o modelo aprende o que os anunciantes pedem, não o que o mercado paga. Diga isso à turma — é a diferença entre um número e um número que significa alguma coisa.

### 2.1 Features do modelo treinado vs. features do modelo implantado

Esta distinção é a fonte mais comum de erro no dia da aula.

- **No notebook (treino)**, as features candidatas podem incluir as categóricas `bairro` e `cidade`, dependendo do que a gold oferecer. Elas entram no `Pipeline` com codificação ajustada **apenas no treino**.
- **No modelo DEPLOYADO no endpoint**, usamos **somente as 5 features numéricas**, nesta **ordem canônica**:

```
[area_util, area_total, quartos, banheiros, garagens]
```

> **Por que só as 5 numéricas no serving.** O container pré-construído de scikit-learn entrega as `instances` ao `predict` como **array posicional**, não como DataFrame com nomes de coluna. Restringir o modelo implantado às features numéricas, numa ordem fixa e documentada, elimina o atrito de casar nomes e ordem no payload. As categóricas continuam disponíveis para exploração no notebook — só não fazem parte do contrato do endpoint.

**Ordem é contrato.** Todo payload enviado ao `/predict` precisa respeitar exatamente a sequência acima. Trocar `area_util` por `area_total` na posição não gera erro — gera uma predição silenciosamente errada.

Exemplo de payload (detalhes em [`04-deploy-endpoint.md`](04-deploy-endpoint.md)):

```json
{
  "instances": [[85.0, 110.0, 3.0, 2.0, 1.0]]
}
```

Lido como: `area_util = 85.0`, `area_total = 110.0`, `quartos = 3`, `banheiros = 2`, `garagens = 1`.

### 2.2 Regras anti-vazamento

Excluir do conjunto de features **qualquer coluna derivada do alvo ou que o revele**:

| Excluir | Motivo |
|---|---|
| `preco_fmt` (ou qualquer versão formatada do preço) | É o alvo em outra representação — vazamento direto |
| Preço por metro quadrado calculado a partir de `preco` | Reconstrói o alvo ao ser multiplicado pela área |
| Faixas, categorias ou rótulos derivados de `preco` | Codificam o alvo de forma agregada |
| Campos de texto livre do anúncio que contenham o valor | O preço costuma aparecer escrito na descrição |

> **Sintoma de vazamento.** Se o MAE do modelo ficar próximo de zero, ou absurdamente melhor que o baseline, **pare e revise as colunas**. Um MAE bom demais quase nunca é um modelo bom — é uma coluna que não deveria estar ali.

### 2.3 Deduplicação e separação dos dados

1. **Deduplicar por imóvel** antes de qualquer separação. A gold pode conter o mesmo imóvel anunciado mais de uma vez (reanúncios, atualizações de preço, múltiplas fontes).
2. Se houver **múltiplas observações do mesmo imóvel**, todas devem ficar **no mesmo conjunto** (treino, validação ou teste). Espalhar o mesmo imóvel entre treino e teste infla a métrica: o modelo "acerta" porque já viu aquele imóvel.
3. A separação deve ser **reprodutível** (semente fixa e critério explícito), para que duas execuções do notebook comparem a mesma coisa.
4. Definir uma **chave de imóvel** antes da aula: identificador próprio da gold ou, na falta dele, uma combinação estável de atributos (por exemplo, endereço normalizado + área). Registrar a escolha.

### 2.4 Pré-processamento

- **Imputação e codificação são ajustadas somente no conjunto de treino** e aplicadas aos demais. Ajustar no dataset inteiro vaza informação da validação e do teste para o modelo.
- As transformações são salvas **junto com o modelo**, dentro do mesmo `Pipeline` do scikit-learn. O artefato registrado no Registry precisa ser autossuficiente: recebe features cruas e devolve predição.

### 2.5 Baseline

O baseline é uma **previsão constante igual à mediana do `preco` do conjunto de treino**, avaliada na mesma validação e com a mesma métrica (MAE).

Ele existe para responder a uma pergunta única e direta: **o modelo aprendeu alguma coisa?** Se o MAE do RandomForest não for menor que o MAE do baseline, o modelo não justifica sua própria existência — e esse é um resultado legítimo de discutir em aula, não um erro a esconder. Ambos os valores são registrados no Experiments como `mae` e `mae_baseline`, lado a lado, em cada run.

---

## 3. Como confirmar o schema da gold

A tabela gold não tem schema fixo. **Confirme antes da aula** o nome exato e as colunas disponíveis, e substitua o placeholder `GOLD_TABLE` no notebook.

### 3.1 Pelo console (caminho da aula)

1. Console do Google Cloud → **BigQuery** → **BigQuery Studio**.
2. No painel **Explorer** à esquerda, expandir o projeto `SEU_PROJECT_ID` → dataset **`aula_pdm`**.
3. Clicar na tabela gold. Na aba **Schema**, conferir nomes e tipos das colunas.
4. Na aba **Details**, conferir a **região** (`us-central1`) e o número de linhas.
5. Na aba **Preview**, olhar algumas linhas reais — é onde se percebe rapidamente colunas de preço formatado, campos nulos e duplicatas evidentes.

### 3.2 Por linha de comando (`bq`)

Listar as tabelas do dataset:

```bash
bq ls --project_id=SEU_PROJECT_ID aula_pdm
```

Ver o schema e os metadados da tabela gold:

```bash
bq show --project_id=SEU_PROJECT_ID --schema --format=prettyjson SEU_PROJECT_ID:aula_pdm.GOLD_TABLE
```

Ver região, número de linhas e tamanho:

```bash
bq show --project_id=SEU_PROJECT_ID --format=prettyjson SEU_PROJECT_ID:aula_pdm.GOLD_TABLE
```

### 3.3 Consultas de sanidade

Rode estas três antes da aula. Elas revelam os problemas que estragam o treino ao vivo.

**Volume e cobertura do alvo:**

```sql
SELECT
  COUNT(*)                                AS linhas,
  COUNTIF(preco IS NULL)                  AS preco_nulo,
  COUNTIF(preco <= 0)                     AS preco_invalido,
  APPROX_QUANTILES(preco, 2)[OFFSET(1)]   AS preco_mediana
FROM `SEU_PROJECT_ID.aula_pdm.GOLD_TABLE`;
```

**Nulos nas features do endpoint:**

```sql
SELECT
  COUNTIF(area_util  IS NULL) AS nulo_area_util,
  COUNTIF(area_total IS NULL) AS nulo_area_total,
  COUNTIF(quartos    IS NULL) AS nulo_quartos,
  COUNTIF(banheiros  IS NULL) AS nulo_banheiros,
  COUNTIF(garagens   IS NULL) AS nulo_garagens
FROM `SEU_PROJECT_ID.aula_pdm.GOLD_TABLE`;
```

**Duplicatas por imóvel** (substituir `CHAVE_IMOVEL` pela chave definida em 2.3):

```sql
SELECT CHAVE_IMOVEL, COUNT(*) AS ocorrencias
FROM `SEU_PROJECT_ID.aula_pdm.GOLD_TABLE`
GROUP BY CHAVE_IMOVEL
HAVING COUNT(*) > 1
ORDER BY ocorrencias DESC
LIMIT 20;
```

### 3.4 Registro da confirmação

Anote o resultado e leve para a aula:

| Campo | Valor confirmado |
|---|---|
| Nome completo da tabela gold | `SEU_PROJECT_ID.aula_pdm.________` |
| Região | `us-central1` |
| Linhas após o recorte | |
| Chave de imóvel usada na dedup | |
| Features numéricas disponíveis | `area_util`, `area_total`, `quartos`, `banheiros`, `garagens` — confirmar cada uma |
| Categóricas disponíveis | `bairro`, `cidade` — apenas para o notebook |
| Colunas excluídas por vazamento | |
| Mediana do `preco` (baseline aproximado) | |

---

## 4. Próximo passo

Ambiente e dados confirmados, siga para [`01-setup-gcp.md`](01-setup-gcp.md) (APIs, IAM, bucket e dataset) e depois para [`02-treino-e-experiments.md`](02-treino-e-experiments.md).

Docentes: o [`roteiro-condutor.md`](roteiro-condutor.md) indica em que momento cada um destes itens aparece na tela.
