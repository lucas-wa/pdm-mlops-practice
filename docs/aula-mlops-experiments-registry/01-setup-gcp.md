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
| `dataform.googleapis.com` | Notebooks do BigQuery Studio |
| `notebooks.googleapis.com` | **Só se** usar Vertex AI Workbench |

Em **APIs & Services > Library**, busque e habilite cada uma — incluindo a **Dataform API**, exigida pelos notebooks do BigQuery Studio. Confira em **Enabled APIs & services**.

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

- [ ] **Enabled APIs**: `aiplatform`, `storage`, `bigquery`, `compute`, `dataform`.
- [ ] **Cloud Storage**: bucket `SEU_PROJECT_ID-mlops-aula` em `us-central1`.
- [ ] **BigQuery**: dataset `aula_pdm` em `us-central1`, com a tabela gold.
- [ ] **Vertex AI > Model Registry** abre em `us-central1` (lista vazia é válido).
- [ ] **BigQuery Studio**: notebook importado e runtime conecta (Passo 6).

---

## Passo 6 — Abrir e rodar o notebook (BigQuery Studio)

O notebook da aula roda no **BigQuery Studio**, em `us-central1`.

**Importar o notebook:**

1. Console → **BigQuery** → painel **Explorer**.
2. Ao lado de **Notebooks**, clique em **View actions > Upload to Notebooks**.
3. **Browse** → selecione [`notebooks/treino_experiments_registry.ipynb`](notebooks/treino_experiments_registry.ipynb) do repositório.
4. Ajuste o **Notebook name**, selecione **Region** `us-central1` → **Upload**.

> Para criar um notebook em branco: na barra de abas do editor, dropdown ao lado de **SQL query** → **Notebook > Empty notebook**.

**Conectar o runtime:** clique em **Connect** — usa o runtime padrão e pode levar alguns minutos. Para escolher outro: dropdown ao lado de **Connect** → **Connect to a runtime** → runtime existente ou **Create new runtime**.

### Se falhar com `Quota 'SSD_TOTAL_GB' exceeded`

> `Falha ao criar o ambiente de execução. Quota 'SSD_TOTAL_GB' exceeded. Limit: 250.0 in region us-central1.`

Cada runtime do Colab Enterprise reserva **~200+ GiB** de SSD do Compute Engine (100 GiB de boot + 100 GiB fixo + o disco de dados do template), e o limite padrão é **250 GiB por região** — ou seja, **não cabem dois runtimes no mesmo projeto**. Soluções, nesta ordem:

1. **Apague runtimes ociosos** — libera a quota na hora. **Vertex AI > Colab Enterprise > Runtimes**, selecione o(s) que não estão em uso → **Delete**, depois reconecte. Em CLI: `gcloud colab runtimes list --region=us-central1` e `gcloud colab runtimes delete RUNTIME_ID --region=us-central1`. Em projeto compartilhado, combine antes de apagar o runtime de outra pessoa.
2. **Recomendado para a turma: cada aluno no próprio projeto** (onde é `Owner`) — assim ninguém divide os 250 GiB.
3. **Peça aumento da quota** `SSD_TOTAL_GB` em `us-central1`: **IAM & Admin > Quotas & System Limits**, filtre por `SSD_TOTAL_GB`, selecione a região → **Edit quota / Request increase**.
4. **Reduza o disco do runtime** com um template customizado: **Colab Enterprise > Runtime templates > Create**, diminua o disco de dados, e use em **Connect > Create new runtime**. Ajuda a caber **um** runtime na quota; não resolve dois no mesmo projeto, porque boot + disco fixo já somam 200 GiB.

Quotas do Colab Enterprise: <https://docs.cloud.google.com/colab/docs/quotas>

**Executar:** rode as células uma a uma (código e SQL), na ordem. Explicação em [`02-treino-e-experiments.md`](02-treino-e-experiments.md).

- **IAM**: `roles/owner` (cada aluno é Owner) já cobre tudo. Em projeto compartilhado, os papéis são `roles/bigquery.studioUser`, `roles/bigquery.jobUser`, `roles/bigquery.readSessionUser`, `roles/aiplatform.notebookRuntimeUser` e `roles/dataform.codeEditor`.
- **Créditos**: o runtime consome **enquanto estiver ativo** (auto-shutdown por inatividade ~180 min). Desligue ao terminar — Passo 2 do checklist em [`05-encerramento-custos.md`](05-encerramento-custos.md).

---

## Referências

- Habilitar APIs: <https://docs.cloud.google.com/apis/docs/getting-started>
- Papéis de IAM do Vertex AI: <https://docs.cloud.google.com/vertex-ai/docs/general/access-control>
- Localização de datasets no BigQuery: <https://docs.cloud.google.com/bigquery/docs/locations>
- Containers pré-construídos de predição: <https://docs.cloud.google.com/vertex-ai/docs/predictions/pre-built-containers>

---

Equivalentes em CLI e IaC: veja [`gcloud/README.md`](gcloud/README.md) e [`terraform/README.md`](terraform/README.md).
