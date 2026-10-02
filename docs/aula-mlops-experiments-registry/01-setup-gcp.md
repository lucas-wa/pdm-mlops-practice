# 01 — Setup da GCP pelo console

Prepara o projeto para a aula de **Vertex AI Experiments + Model Registry + Endpoint**. Este é o caminho
usado na condução ao vivo.

> **Aviso de rebrand.** A documentação da Google já aparece como **"Gemini Enterprise Agent Platform"**,
> mas **no console o produto continua rotulado "Vertex AI"**. Se um menu citado aqui estiver com outro
> rótulo, procure o mesmo caminho sob o novo nome — serviços e APIs (`aiplatform.googleapis.com`) não
> mudaram.

## Convenções desta aula

Usadas por todos os materiais (notebook, scripts, Terraform). Trocar um nome quebra os passos seguintes.

| Item | Valor |
|---|---|
| Região | `us-central1` |
| Zona (quando exigida) | `us-central1-a` |
| Projeto | `SEU_PROJECT_ID` |
| Conta de faturamento | `SEU_BILLING_ACCOUNT_ID` |
| Bucket de artefatos da aula (**novo**) | `SEU_PROJECT_ID-mlops-aula` |
| Bucket compartilhado de aulas anteriores | `SEU_PROJECT_ID-aula-pdm` — **não mexer** |
| Dataset BigQuery (existente) | `aula_pdm` |
| Tabela gold | `GOLD_TABLE` (ex.: `aula_pdm.imoveis_gold`) |
| Experiment | `preco-imoveis-rf` |
| Modelo (display name) | `rf-preco-imoveis` |
| Endpoint (display name) | `rf-preco-imoveis-endpoint` |
| Diretório do artefato | `gs://SEU_PROJECT_ID-mlops-aula/models/rf/` |
| Arquivo do artefato | `gs://SEU_PROJECT_ID-mlops-aula/models/rf/model.joblib` |
| Container de serving | `us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest` |

Dois pontos que costumam gerar confusão:

1. O bucket da aula é **novo e dedicado** (`-mlops-aula`). O `-aula-pdm`, das aulas anteriores, **não é
   tocado** por nada deste diretório.
2. O `artifact_uri` do Model Registry aponta para o **diretório** (`.../models/rf/`), não para o arquivo.
   E o arquivo **precisa** se chamar `model.joblib` (não `.pkl`), que é o nome procurado pelo container
   pré-construído de scikit-learn.

---

## Passo 0 — Pré-requisitos

1. Confirme o projeto correto no seletor, no topo da barra.
2. **Billing > Overview**: o projeto precisa estar vinculado a uma conta de faturamento ativa. Se
   aparecer "This project has no billing account", use **Billing > Link a billing account**.
3. Anote o **Project ID** (não o *Project name* — são diferentes).

---

## Passo 1 — Habilitar as APIs

| API | Por quê |
|---|---|
| `aiplatform.googleapis.com` | **Obrigatória.** Experiments, Model Registry, Endpoints |
| `storage.googleapis.com` | Guardar o `model.joblib` no Cloud Storage |
| `bigquery.googleapis.com` | Ler a camada gold |
| `compute.googleapis.com` | Máquinas do deploy e do runtime do notebook |
| `notebooks.googleapis.com` | **Só se** a turma usar Vertex AI Workbench |

1. **APIs & Services > Library**.
2. Busque `Vertex AI API` → abra o card → **Enable**.
3. Repita para `Cloud Storage API`, `BigQuery API` e `Compute Engine API`.
4. Confira em **APIs & Services > Enabled APIs & services**.

A Vertex AI API leva um ou dois minutos e habilita dependentes automaticamente.

---

## Passo 2 — IAM (opcional — você pode pular)

> **Cada aluno é `Owner` do próprio projeto.** `roles/owner` já concede tudo o que a aula precisa —
> Vertex AI, Cloud Storage, BigQuery e habilitar APIs. **Não é preciso conceder nenhum papel.** Siga
> direto para o Passo 3.

O que segue é referência para **projeto compartilhado** ou **service account dedicada** (menor
privilégio, o padrão correto fora da sala de aula).

| Papel | Para quê |
|---|---|
| `roles/aiplatform.user` | Criar runs, registrar modelo, criar endpoint e predizer |
| `roles/storage.objectAdmin` | Escrever e ler `model.joblib` no bucket da aula |
| `roles/bigquery.dataViewer` | Ler a tabela gold |
| `roles/bigquery.jobUser` | Executar as consultas |

1. **IAM & Admin > IAM** → **Grant access**.
2. Em **New principals**, o e-mail do usuário ou da conta de serviço.
3. Em **Assign roles**, adicione um papel por vez com **+ Add another role**: `Vertex AI User`,
   `Storage Object Admin`, `BigQuery Data Viewer`, `BigQuery Job User`.
4. **Save**.

Para criar a conta de serviço antes: **IAM & Admin > Service Accounts > Create service account** — pule
a atribuição de papéis nessa tela e use o caminho acima.

---

## Passo 3 — Criar o bucket dedicado da aula

Separado do `-aula-pdm` para que o teardown possa esvaziá-lo sem risco de levar junto dados das aulas
passadas.

1. **Cloud Storage > Buckets** → **Create**.
2. **Name your bucket**: `SEU_PROJECT_ID-mlops-aula` (nome é global; o prefixo do projeto costuma
   resolver conflitos).
3. **Choose where to store your data**: `Region` → `us-central1 (Iowa)` — a **mesma região** do dataset
   BigQuery e dos recursos Vertex AI.
4. **Choose a storage class**: `Standard`.
5. **Choose how to control access**: marque **Enforce public access prevention**; **Access control**:
   `Uniform`.
6. **Choose how to protect object data**: padrão (`None`).
7. **Create**.

---

## Passo 4 — Confirmar (ou criar) o dataset `aula_pdm`

O dataset normalmente **já existe** desde as aulas anteriores. Aqui o objetivo é **confirmar**.

1. **BigQuery** (menu do console, sob *Analytics*).
2. No painel **Explorer**, expanda o projeto e procure `aula_pdm`.
3. Clique no dataset e confira, em **Details**, que **Data location** é `us-central1`.
4. Expanda o dataset e **anote o nome exato da tabela gold**; na aba **Schema**, confira as colunas
   (você vai precisar delas no notebook, no lugar do placeholder `GOLD_TABLE`).
5. **Se não existir**: três pontos ao lado do projeto > **Create dataset** → *Dataset ID* `aula_pdm` →
   *Location type* `Region` → `us-central1` → **Create dataset**.

---

## Passo 5 — Verificação final

Antes de abrir o notebook, confirme no console:

- [ ] **APIs & Services > Enabled APIs**: `aiplatform`, `storage`, `bigquery`, `compute` habilitadas.
- [ ] **Cloud Storage > Buckets**: `SEU_PROJECT_ID-mlops-aula` existe, em `us-central1`.
- [ ] **BigQuery > Explorer**: dataset `aula_pdm` em `us-central1`, com a tabela gold.
- [ ] **Vertex AI > Model Registry** abre em `us-central1` (lista vazia é resultado válido).

---

## Referências

- Habilitar APIs: <https://docs.cloud.google.com/apis/docs/getting-started>
- Papéis de IAM do Vertex AI: <https://docs.cloud.google.com/vertex-ai/docs/general/access-control>
- Localização de datasets no BigQuery: <https://docs.cloud.google.com/bigquery/docs/locations>
- Containers pré-construídos de predição: <https://docs.cloud.google.com/vertex-ai/docs/predictions/pre-built-containers>

---

Equivalentes em CLI e IaC: veja [`gcloud/README.md`](gcloud/README.md) e [`terraform/README.md`](terraform/README.md).
