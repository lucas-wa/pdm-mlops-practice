# 00 — Pré-requisitos e camada gold

O que precisa estar pronto no GCP **antes da aula** e o contrato de dados (alvo, features, exclusões).

> **Créditos educacionais.** O consumo é real — veja o [`README.md`](README.md). O encerramento em [`05-encerramento-custos.md`](05-encerramento-custos.md) é parte obrigatória da atividade.

---

## 1. Checklist de pré-requisitos

### 1.1 Conta e projeto

- [ ] Projeto GCP próprio, com **Project ID anotado** (`SEU_PROJECT_ID` em todos os comandos).
- [ ] **Faturamento ativo**, vinculado aos créditos educacionais. Sem billing, a API do Vertex AI não habilita.
- [ ] Conta de faturamento anotada (`SEU_BILLING_ACCOUNT_ID`).
- [ ] **Budget com alerta** configurado antes de criar qualquer recurso — ver [`05-encerramento-custos.md`](05-encerramento-custos.md).

### 1.2 Permissões

- [ ] Você é **`Owner`** do próprio projeto (`roles/owner`) — **não precisa conceder nada**.

Referência **apenas para projeto compartilhado** ou service account dedicada:

| Papel | Para quê |
|---|---|
| `roles/aiplatform.user` | Criar runs no Experiments, registrar modelo, criar endpoint, predizer |
| `roles/storage.objectAdmin` | Gravar e ler `model.joblib` no bucket da aula |
| `roles/bigquery.dataViewer` | Ler a tabela gold |
| `roles/bigquery.jobUser` | Executar as consultas |

Comandos de concessão em [`gcloud/README.md`](gcloud/README.md) e [`gcloud/00_setup.sh`](gcloud/00_setup.sh).

### 1.3 APIs habilitadas

- [ ] `aiplatform.googleapis.com` (obrigatória)
- [ ] `storage.googleapis.com`
- [ ] `bigquery.googleapis.com`
- [ ] `compute.googleapis.com` (nós do endpoint)

Passo a passo em [`01-setup-gcp.md`](01-setup-gcp.md).

### 1.4 Recursos

- [ ] Dataset **`aula_pdm`** em **`us-central1`**, com a tabela gold populada.
- [ ] Bucket da aula **`${PROJECT_ID}-mlops-aula`** criado em `us-central1`.
- [ ] Bucket compartilhado **`${PROJECT_ID}-aula-pdm`** preservado — **não mexer**.

> **Região.** Dataset, bucket, experimento, modelo e endpoint, todos em **`us-central1`**. O Vertex AI não lê datasets do BigQuery de outra região sem cópia intermediária.

### 1.5 Ambiente de execução

- [ ] Acesso ao **BigQuery Studio** no console (runtime por baixo: Colab Enterprise).
- [ ] Notebook [`notebooks/treino_experiments_registry.ipynb`](notebooks/treino_experiments_registry.ipynb) aberto, com a primeira célula de instalação executada.

> **O runtime consome créditos enquanto ativo.** Há desligamento por inatividade (~180 min), mas apagar o runtime ao final é o que garante o encerramento.

### 1.6 A confirmar ao vivo, antes da aula

- [ ] **Nome exato da tabela gold** e colunas desta turma (o schema não é fixo — a gold foi construída pelos alunos).
- [ ] **Rótulos do console**: a doc diz "Gemini Enterprise Agent Platform", o console ainda exibe **"Vertex AI"**. Confirmar onde estão Experiments, Model Registry e Online prediction.
- [ ] **Tag do container de serving** scikit-learn, casando com a versão usada no treino (ver [`03-model-registry.md`](03-model-registry.md)).
- [ ] **Tempo de provisionamento do endpoint**, para dimensionar o roteiro.

---

## 2. Contrato de dados

Vale para o notebook, o modelo registrado e o payload do endpoint. Vem de `docs/planejamento-aulas-mlops-gcp.md` e **não muda durante a aula**.

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

> **O alvo é preço de anúncio.** O modelo aprende o que os anunciantes pedem, não o que o mercado paga — diga isso à turma ao interpretar o erro.

### 2.1 Features do treino vs. features do deploy

Fonte mais comum de erro no dia da aula.

- **No notebook (treino)**: as candidatas podem incluir as categóricas `bairro` e `cidade`, codificadas dentro do `Pipeline` e ajustadas **apenas no treino**.
- **No modelo DEPLOYADO**: **somente as 5 features numéricas**, nesta **ordem canônica**:

```
[area_util, area_total, quartos, banheiros, garagens]
```

> **Por que só as 5 numéricas no serving.** O container pré-construído entrega as `instances` ao `predict` como **array posicional**, não como DataFrame com nomes de coluna. Ordem fixa e documentada elimina o atrito de casar nomes no payload. As categóricas seguem disponíveis para exploração no notebook.

**Ordem é contrato.** Trocar `area_util` por `area_total` na posição não gera erro — gera predição silenciosamente errada.

Exemplo de payload (detalhes em [`04-deploy-endpoint.md`](04-deploy-endpoint.md)):

```json
{
  "instances": [[85.0, 110.0, 3.0, 2.0, 1.0]]
}
```

Lido como: `area_util = 85.0`, `area_total = 110.0`, `quartos = 3`, `banheiros = 2`, `garagens = 1`.

### 2.2 Regras anti-vazamento

Excluir das features **qualquer coluna derivada do alvo ou que o revele**:

| Excluir | Motivo |
|---|---|
| `preco_fmt` (ou qualquer versão formatada do preço) | É o alvo em outra representação — vazamento direto |
| Preço por metro quadrado calculado a partir de `preco` | Reconstrói o alvo ao ser multiplicado pela área |
| Faixas, categorias ou rótulos derivados de `preco` | Codificam o alvo de forma agregada |
| Campos de texto livre do anúncio que contenham o valor | O preço costuma aparecer escrito na descrição |

> **Sintoma de vazamento.** MAE próximo de zero, ou absurdamente melhor que o baseline: **pare e revise as colunas**.

### 2.3 Deduplicação e separação dos dados

1. **Deduplicar por imóvel** antes de qualquer separação — a gold pode repetir o mesmo imóvel (reanúncios, atualizações de preço, múltiplas fontes).
2. **Múltiplas observações do mesmo imóvel ficam no mesmo conjunto.** Espalhá-las entre treino e teste infla a métrica: o modelo "acerta" porque já viu aquele imóvel.
3. A separação deve ser **reprodutível** (semente fixa e critério explícito).
4. Definir a **chave de imóvel** antes da aula: identificador próprio da gold ou combinação estável de atributos (endereço normalizado + área). Registrar a escolha.

### 2.4 Pré-processamento

- **Imputação e codificação são ajustadas somente no treino** e aplicadas aos demais. Ajustar no dataset inteiro vaza informação da validação e do teste.
- As transformações são salvas **junto com o modelo**, no mesmo `Pipeline`: o artefato recebe features cruas e devolve predição.

### 2.5 Baseline

Previsão constante igual à **mediana do `preco` do conjunto de treino**, avaliada na mesma validação e com a mesma métrica (MAE).

Responde a uma pergunta só: **o modelo aprendeu alguma coisa?** Se o MAE do RandomForest não for menor que o do baseline, o modelo não se justifica — resultado legítimo de discutir em aula. Ambos vão para o Experiments como `mae` e `mae_baseline`, em cada run.

---

## 3. Como confirmar o schema da gold

A gold não tem schema fixo. Confirme o nome exato e as colunas, e substitua o placeholder `GOLD_TABLE` no notebook.

> **Não tem a gold, ou está mal formatada?** Rode [`gcloud/seed_gold.sh`](gcloud/seed_gold.sh) no Cloud Shell — instruções no **Passo 4** de [`01-setup-gcp.md`](01-setup-gcp.md).

### 3.1 Pelo console (caminho da aula)

1. **BigQuery** → **BigQuery Studio**.
2. Painel **Explorer**: expandir `SEU_PROJECT_ID` → dataset **`aula_pdm`**.
3. Clicar na tabela gold → aba **Schema**: nomes e tipos das colunas.
4. Aba **Details**: região (`us-central1`) e número de linhas.
5. Aba **Preview**: linhas reais — onde aparecem preço formatado, nulos e duplicatas evidentes.

### 3.2 Por linha de comando (`bq`)

Listar as tabelas do dataset:

```bash
bq ls --project_id=SEU_PROJECT_ID aula_pdm
```

Schema da tabela gold:

```bash
bq show --project_id=SEU_PROJECT_ID --schema --format=prettyjson SEU_PROJECT_ID:aula_pdm.GOLD_TABLE
```

Região, número de linhas e tamanho:

```bash
bq show --project_id=SEU_PROJECT_ID --format=prettyjson SEU_PROJECT_ID:aula_pdm.GOLD_TABLE
```

### 3.3 Consultas de sanidade

Rode as três antes da aula.

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

Siga para [`01-setup-gcp.md`](01-setup-gcp.md) (APIs, IAM, bucket e dataset) e depois para [`02-treino-e-experiments.md`](02-treino-e-experiments.md).

Docentes: o [`roteiro-condutor.md`](roteiro-condutor.md) indica em que momento cada item aparece na tela.
