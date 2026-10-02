# 01 — Setup da GCP pelo console

Prepara o projeto para **Vertex AI Experiments + Model Registry + Endpoint**.

> **Rebrand.** No console o produto ainda é "Vertex AI"; na doc pode aparecer "Gemini Enterprise Agent Platform". APIs não mudaram.

## Convenções desta aula

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

- O bucket da aula é novo e dedicado (`-mlops-aula`); nada aqui toca o `-aula-pdm`.
- `artifact_uri` aponta para o **diretório** (`.../models/rf/`), e o arquivo **precisa** se chamar `model.joblib` — é o nome que o container scikit-learn procura.

---

## Passo 0 — Pré-requisitos

- Projeto correto selecionado no seletor do topo.
- **Billing > Overview**: projeto vinculado a uma conta de faturamento ativa.
- Anote o **Project ID** (não o *Project name*).

---

## Passo 1 — Habilitar as APIs

| API | Por quê |
|---|---|
| `aiplatform.googleapis.com` | **Obrigatória.** Experiments, Model Registry, Endpoints |
| `storage.googleapis.com` | Guardar o `model.joblib` |
| `bigquery.googleapis.com` | Ler a camada gold |
| `compute.googleapis.com` | Máquinas do deploy |
| `notebooks.googleapis.com` | **Só se** usar Vertex AI Workbench |

Em **APIs & Services > Library**, busque e habilite cada uma. Confira em **Enabled APIs & services**.

---

## Passo 2 — IAM (opcional — pode pular)

> **Cada aluno é `Owner` do próprio projeto.** `roles/owner` já cobre tudo. **Não é preciso conceder nada** — siga para o Passo 3.

Referência para **projeto compartilhado** ou **service account dedicada**:

| Papel | Para quê |
|---|---|
| `roles/aiplatform.user` | Criar runs, registrar modelo, criar endpoint e predizer |
| `roles/storage.objectAdmin` | Escrever e ler `model.joblib` no bucket da aula |
| `roles/bigquery.dataViewer` | Ler a tabela gold |
| `roles/bigquery.jobUser` | Executar as consultas |

Conceder em **IAM & Admin > IAM > Grant access**: principal (usuário ou service account) + os papéis acima, um por vez com **+ Add another role**. Para criar a conta antes: **IAM & Admin > Service Accounts > Create service account**.

---

## Passo 3 — Criar o bucket dedicado

**Cloud Storage > Buckets > Create**:

- **Name**: `SEU_PROJECT_ID-mlops-aula`
- **Location**: `Region` → `us-central1 (Iowa)`
- **Storage class**: `Standard`
- **Access control**: `Uniform` + **Enforce public access prevention**
- Demais opções: padrão → **Create**

---

## Passo 4 — Garantir a camada gold

**Se a gold já existe** — em **BigQuery > Explorer**:

1. Expanda o projeto e abra `aula_pdm`; em **Details**, confirme **Data location** `us-central1`.
2. Anote o **nome exato da tabela gold** (substitui `GOLD_TABLE` no notebook).
3. Na aba **Schema**, confira as colunas.

**Se não existe ou está mal formatada** — no **Cloud Shell**:

```bash
git clone https://github.com/lucas-wa/pdm-mlops-practice.git
cd pdm-mlops-practice/docs/aula-mlops-experiments-registry
bash gcloud/seed_gold.sh
```

O script [`gcloud/seed_gold.sh`](gcloud/seed_gold.sh) valida a gold e, só se faltar ou estiver inválida, reconstrói a partir da amostra do repositório. Use `--force` para reconstruir mesmo com a gold válida.

> Ele escreve **apenas no dataset `aula_pdm`** (BigQuery) — sem bucket, sem endpoint, sem custo por node-hora. Testado em Cloud Shell.

---

## Passo 5 — Verificação final

- [ ] **Enabled APIs**: `aiplatform`, `storage`, `bigquery`, `compute`.
- [ ] **Cloud Storage**: bucket `SEU_PROJECT_ID-mlops-aula` em `us-central1`.
- [ ] **BigQuery**: dataset `aula_pdm` em `us-central1`, com a tabela gold.
- [ ] **Vertex AI > Model Registry** abre em `us-central1` (lista vazia é válido).

---

## Referências

- Habilitar APIs: <https://docs.cloud.google.com/apis/docs/getting-started>
- Papéis de IAM do Vertex AI: <https://docs.cloud.google.com/vertex-ai/docs/general/access-control>
- Localização de datasets no BigQuery: <https://docs.cloud.google.com/bigquery/docs/locations>
- Containers pré-construídos de predição: <https://docs.cloud.google.com/vertex-ai/docs/predictions/pre-built-containers>

---

Equivalentes em CLI e IaC: veja [`gcloud/README.md`](gcloud/README.md) e [`terraform/README.md`](terraform/README.md).
