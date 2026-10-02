# 01 — Setup da GCP (Console | gcloud | Terraform)

Este documento prepara o projeto GCP para a aula de **Vertex AI Experiments + Model Registry +
Endpoint**. Cada passo aparece em três blocos com a mesma numeração:

- **Console (aula)** — o caminho usado na condução ao vivo.
- **gcloud** — o equivalente em linha de comando.
- **Terraform** — o equivalente declarativo, já materializado em `terraform/`.

Os três caminhos produzem o mesmo resultado. Escolha **um** por passo; não é necessário
executar os três.

> **Aviso de rebrand.** A documentação da Google está migrando o nome do produto para
> **"Gemini Enterprise Agent Platform"**, e vários links de docs já respondem sob esse nome.
> **No console, no período do curso, o produto continua rotulado "Vertex AI"**. Se um menu
> citado aqui aparecer com outro rótulo, procure pelo mesmo caminho sob o novo nome — os
> serviços, as APIs (`aiplatform.googleapis.com`) e os comandos `gcloud ai ...` não mudaram.

---

## Convenções desta aula

Estes nomes são usados por **todos** os materiais da aula (notebook, scripts, Terraform).
Mantenha-os exatamente como estão; trocar um nome quebra os passos seguintes.

| Item | Valor |
|---|---|
| Região | `us-central1` |
| Zona (quando exigida) | `us-central1-a` |
| Projeto | `SEU_PROJECT_ID` (substitua pelo seu) |
| Conta de faturamento | `SEU_BILLING_ACCOUNT_ID` (substitua pela sua) |
| Bucket de artefatos da aula (**novo**) | `SEU_PROJECT_ID-mlops-aula` |
| Bucket compartilhado de aulas anteriores | `SEU_PROJECT_ID-aula-pdm` — **não mexer** |
| Dataset BigQuery (existente) | `aula_pdm` |
| Tabela gold | `GOLD_TABLE` (por exemplo, `aula_pdm.imoveis_gold`) |
| Experiment | `preco-imoveis-rf` |
| Modelo (display name) | `rf-preco-imoveis` |
| Endpoint (display name) | `rf-preco-imoveis-endpoint` |
| Diretório do artefato | `gs://SEU_PROJECT_ID-mlops-aula/models/rf/` |
| Arquivo do artefato | `gs://SEU_PROJECT_ID-mlops-aula/models/rf/model.joblib` |
| Container de serving | `us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest` |

Dois pontos que costumam gerar confusão:

1. O bucket da aula é **novo e dedicado** (`-mlops-aula`). O bucket `-aula-pdm`, das aulas
   anteriores, continua existindo e **não é tocado** por nenhum script deste diretório.
2. O `artifact_uri` do Model Registry aponta para o **diretório** (`.../models/rf/`), não para
   o arquivo. E o arquivo **precisa** se chamar `model.joblib` (não `.pkl`) para o container
   pré-construído de scikit-learn encontrá-lo.

---

## Passo 0 — Pré-requisitos

Antes de qualquer passo, confirme que você tem um projeto com faturamento ativo e que o
`gcloud` está apontando para ele.

### Console (aula)

1. Abra o seletor de projetos no topo da barra e confirme o projeto correto.
2. **Billing > Overview**: o projeto precisa estar vinculado a uma conta de faturamento ativa.
   Se aparecer "This project has no billing account", use **Billing > Link a billing account**.
3. Anote o **Project ID** (não o *Project name* — são diferentes).

### gcloud

```bash
# Autenticar e escolher o projeto
gcloud auth login
gcloud config set project SEU_PROJECT_ID
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a

# Conferir a conta de faturamento vinculada
gcloud billing projects describe SEU_PROJECT_ID

# Se ainda não estiver vinculada:
gcloud billing projects link SEU_PROJECT_ID \
  --billing-account=SEU_BILLING_ACCOUNT_ID
```

### Terraform

```bash
# Credenciais que o provider google usa (Application Default Credentials)
gcloud auth application-default login

cd docs/aula-mlops-experiments-registry/terraform
cp terraform.tfvars.example terraform.tfvars
# edite terraform.tfvars e troque SEU_PROJECT_ID pelo seu Project ID

terraform init
terraform plan
```

O Terraform **não** cria o projeto nem vincula faturamento neste material: ambos são
pré-requisitos.

---

## Passo 1 — Habilitar as APIs

APIs necessárias:

| API | Por quê |
|---|---|
| `aiplatform.googleapis.com` | **Obrigatória.** Experiments, Model Registry, Endpoints. |
| `storage.googleapis.com` | Guardar o `model.joblib` no Cloud Storage. |
| `bigquery.googleapis.com` | Ler a camada gold. |
| `compute.googleapis.com` | Máquinas por trás do deploy no endpoint e do runtime do notebook. |
| `notebooks.googleapis.com` | **Só se** a turma usar Vertex AI Workbench. No BigQuery Studio não é necessária. |

### Console (aula)

1. **APIs & Services > Library**.
2. Busque por `Vertex AI API` → abra o card → **Enable**.
3. Repita para `Cloud Storage API`, `BigQuery API` e `Compute Engine API`.
4. Só se for usar Workbench: repita para `Notebooks API`.
5. Confira o resultado em **APIs & Services > Enabled APIs & services**.

A habilitação da Vertex AI API pode levar um ou dois minutos e habilita APIs dependentes
automaticamente.

### gcloud

```bash
gcloud services enable \
  aiplatform.googleapis.com \
  storage.googleapis.com \
  bigquery.googleapis.com \
  compute.googleapis.com \
  --project=SEU_PROJECT_ID

# Somente se a turma usar Vertex AI Workbench:
gcloud services enable notebooks.googleapis.com --project=SEU_PROJECT_ID

# Conferir
gcloud services list --enabled --project=SEU_PROJECT_ID
```

`gcloud services enable` é idempotente: reexecutar com uma API já habilitada não dá erro.

### Terraform

Em `terraform/main.tf`:

```hcl
resource "google_project_service" "aula" {
  for_each = toset(local.apis)

  project = var.project_id
  service = each.value

  # Não desabilita a API em `terraform destroy`: desabilitar API é uma ação
  # de projeto inteiro e pode derrubar recursos de outras aulas.
  disable_on_destroy = false
}
```

Para incluir a API do Workbench, descomente `notebooks.googleapis.com` na lista `local.apis`.

---

## Passo 2 — Conceder IAM (menor privilégio)

> ## ⚠️ Este passo é opcional — você pode pular
>
> **Nesta disciplina, cada aluno é `Owner` do próprio projeto GCP.** O papel `roles/owner`
> já concede **tudo** o que a aula precisa — Vertex AI, Cloud Storage, BigQuery e habilitar
> APIs. **Não é preciso conceder nenhum papel.**
>
> Leia o restante do passo como **material informativo** e siga direto para o
> **Passo 3 — Criar o bucket dedicado da aula**.

O que vem abaixo é **referência para outro cenário**: projeto **compartilhado** (vários
alunos ou equipes no mesmo projeto) ou uma **conta de serviço dedicada** executando a aula
com menor privilégio — que é o padrão correto fora da sala de aula. **Não é o caso do
aluno-Owner.**

Papéis mínimos para executar a aula ponta a ponta nesse cenário:

| Papel | Para quê |
|---|---|
| `roles/aiplatform.user` | Criar runs de Experiment, registrar modelo, criar endpoint e predizer. |
| `roles/storage.objectAdmin` | Escrever e ler `model.joblib` no bucket da aula. |
| `roles/bigquery.dataViewer` | Ler a tabela gold. |
| `roles/bigquery.jobUser` | Executar as consultas (um job de query custa cota de job). |

O *principal* que recebe os papéis pode ser:

- um usuário: `user:seu-email@dominio.com`
- uma conta de serviço: `serviceAccount:NOME@SEU_PROJECT_ID.iam.gserviceaccount.com`

### Console (aula) — referência: projeto compartilhado ou service account

1. **IAM & Admin > IAM**.
2. Botão **Grant access** (topo da tabela).
3. Em **New principals**, informe o e-mail do usuário ou da conta de serviço.
4. Em **Assign roles**, adicione um papel por vez com **+ Add another role**:
   `Vertex AI User`, `Storage Object Admin`, `BigQuery Data Viewer`, `BigQuery Job User`.
5. **Save**.

Para criar a conta de serviço antes: **IAM & Admin > Service Accounts > Create service
account**, informe nome e ID, e pule a atribuição de papéis nessa tela (faça pelo passo acima,
que é o caminho canônico).

### gcloud — referência: projeto compartilhado ou service account

```bash
PROJECT_ID="SEU_PROJECT_ID"
# Troque pelo principal que vai executar a aula:
MEMBER="user:seu-email@dominio.com"
# ou: MEMBER="serviceAccount:aula-mlops@${PROJECT_ID}.iam.gserviceaccount.com"

for ROLE in \
  roles/aiplatform.user \
  roles/storage.objectAdmin \
  roles/bigquery.dataViewer \
  roles/bigquery.jobUser
do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="${MEMBER}" \
    --role="${ROLE}" \
    --condition=None
done

# Conferir o que ficou concedido a esse principal
gcloud projects get-iam-policy "${PROJECT_ID}" \
  --flatten="bindings[].members" \
  --filter="bindings.members:${MEMBER}" \
  --format="table(bindings.role)"
```

`add-iam-policy-binding` é idempotente: reconceder um papel já concedido não gera erro nem
duplica a binding.

### Terraform — referência: projeto compartilhado ou service account

Este bloco **não** está em `terraform/main.tf`, porque a aula assume que o aluno é Owner do
próprio projeto e porque escrever IAM de projeto via Terraform em um projeto compartilhado
exige cuidado. Se você quiser gerenciar os papéis declarativamente, acrescente ao `main.tf`:

```hcl
variable "iam_member" {
  description = "Principal que executa a aula, no formato user:... ou serviceAccount:..."
  type        = string
  default     = "" # vazio = nenhuma binding criada
}

resource "google_project_iam_member" "aula" {
  for_each = var.iam_member == "" ? toset([]) : toset([
    "roles/aiplatform.user",
    "roles/storage.objectAdmin",
    "roles/bigquery.dataViewer",
    "roles/bigquery.jobUser",
  ])

  project = var.project_id
  role    = each.value
  member  = var.iam_member
}
```

**Nunca** use `google_project_iam_policy` aqui: ele é **autoritativo** e substitui a política
inteira do projeto, removendo todas as bindings que não estiverem no seu código — inclusive as
das aulas anteriores e a sua própria. Use `google_project_iam_member` (aditivo, por
principal+papel).

---

## Passo 3 — Criar o bucket dedicado da aula

Nome: `SEU_PROJECT_ID-mlops-aula`, região `us-central1`, acesso uniforme.

Este bucket é **novo e separado** do `SEU_PROJECT_ID-aula-pdm` usado nas aulas anteriores.
A separação existe para que o teardown do fim da aula possa apagar o bucket inteiro sem risco
de levar junto dados das aulas passadas.

### Console (aula)

1. **Cloud Storage > Buckets** → **Create**.
2. **Name your bucket**: `SEU_PROJECT_ID-mlops-aula`
   (o nome é global; se der conflito, o projeto no prefixo normalmente já resolve).
3. **Choose where to store your data**: `Region` → `us-central1 (Iowa)`.
   Precisa ser a **mesma região** do dataset BigQuery e dos recursos Vertex AI.
4. **Choose a storage class**: `Standard`.
5. **Choose how to control access**:
   - marque **Enforce public access prevention on this bucket**;
   - **Access control**: `Uniform` (acesso uniforme por bucket).
6. **Choose how to protect object data**: deixe o padrão (`None`).
7. **Create**.

### gcloud

```bash
PROJECT_ID="SEU_PROJECT_ID"
BUCKET="${PROJECT_ID}-mlops-aula"

# Criar só se ainda não existir
if gcloud storage buckets describe "gs://${BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Bucket gs://${BUCKET} ja existe."
else
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="${PROJECT_ID}" \
    --location=us-central1 \
    --default-storage-class=STANDARD \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

# Conferir
gcloud storage buckets describe "gs://${BUCKET}" \
  --format="value(name, location, uniform_bucket_level_access)"
```

### Terraform

Em `terraform/main.tf`:

```hcl
resource "google_storage_bucket" "artefatos_aula" {
  name     = local.bucket_name # "${var.project_id}-mlops-aula"
  project  = var.project_id
  location = var.region

  # force_destroy = true permite que `terraform destroy` apague o bucket mesmo
  # com objetos dentro. É aceitável porque este bucket é EXCLUSIVO da aula.
  force_destroy               = true
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  storage_class               = "STANDARD"

  depends_on = [google_project_service.aula]
}
```

---

## Passo 4 — Confirmar (ou criar) o dataset `aula_pdm`

O dataset `aula_pdm` normalmente **já existe** desde as aulas anteriores, na região
`us-central1`. O objetivo aqui é **confirmar**, e só criar se estiver faltando.

Confirme também o nome real da tabela gold e anote-o: o notebook da aula usa o placeholder
`GOLD_TABLE` (por exemplo, `aula_pdm.imoveis_gold`).

### Console (aula)

1. **BigQuery** (no menu do console, sob *Analytics*).
2. No painel **Explorer** à esquerda, expanda o seu projeto e procure o dataset `aula_pdm`.
3. Clique no dataset e confira, no painel **Details**, que **Data location** é `us-central1`.
4. Expanda o dataset e anote o nome exato da tabela gold; abra a aba **Schema** e confira as
   colunas disponíveis (você vai precisar delas no notebook).
5. **Se o dataset não existir**: clique nos três pontos ao lado do nome do projeto >
   **Create dataset** → *Dataset ID* `aula_pdm` → *Location type* `Region` →
   `us-central1` → **Create dataset**.

### gcloud

```bash
PROJECT_ID="SEU_PROJECT_ID"
DATASET="aula_pdm"

# Confirmar que existe e em que região
bq --project_id="${PROJECT_ID}" show --format=prettyjson "${PROJECT_ID}:${DATASET}" \
  | grep -E '"location"|"datasetId"'

# Criar apenas se estiver faltando
bq --project_id="${PROJECT_ID}" --location=us-central1 mk \
  --dataset \
  --description="Dados da disciplina PDM (camada gold)" \
  "${PROJECT_ID}:${DATASET}"

# Listar as tabelas para descobrir o nome real da gold
bq --project_id="${PROJECT_ID}" ls "${PROJECT_ID}:${DATASET}"

# Conferir o schema da tabela gold (troque GOLD_TABLE)
bq --project_id="${PROJECT_ID}" show --schema --format=prettyjson "${PROJECT_ID}:GOLD_TABLE"
```

### Terraform

```hcl
# ATENÇÃO: este dataset provavelmente JÁ EXISTE (aulas anteriores).
# Um `terraform apply` sem importar vai falhar com "Already Exists".
# Importe antes de aplicar:
#
#   terraform import google_bigquery_dataset.aula_pdm \
#     projects/SEU_PROJECT_ID/datasets/aula_pdm
#
resource "google_bigquery_dataset" "aula_pdm" {
  dataset_id  = "aula_pdm"
  project     = var.project_id
  location    = var.region
  description = "Dados da disciplina PDM (camada gold)"

  # NÃO apagar o conteúdo junto com o dataset.
  delete_contents_on_destroy = false

  lifecycle {
    # Infra compartilhada de aulas anteriores: `terraform destroy` deve falhar
    # em vez de apagar. Ver "Teardown" abaixo.
    prevent_destroy = true
  }

  depends_on = [google_project_service.aula]
}
```

---

## Passo 5 — Verificação final

Rode esta checagem antes de abrir o notebook. Tudo precisa responder sem erro.

```bash
PROJECT_ID="SEU_PROJECT_ID"
BUCKET="${PROJECT_ID}-mlops-aula"

# 1. APIs habilitadas (deve listar aiplatform, storage, bigquery, compute)
gcloud services list --enabled --project="${PROJECT_ID}" \
  --filter="config.name:(aiplatform.googleapis.com OR storage.googleapis.com OR bigquery.googleapis.com OR compute.googleapis.com)" \
  --format="value(config.name)"

# 2. Bucket da aula existe e está em us-central1
gcloud storage buckets describe "gs://${BUCKET}" --format="value(name, location)"

# 3. Dataset existe
bq --project_id="${PROJECT_ID}" show --dataset "${PROJECT_ID}:aula_pdm"

# 4. A API do Vertex AI responde na região da aula (lista vazia é resultado válido)
gcloud ai models list --region=us-central1 --project="${PROJECT_ID}"
```

Alternativa em um comando só: `bash scripts/00_setup.sh` faz os passos 1, 2, 3 e 4 de forma
idempotente.

---

## O que o Terraform **NÃO** faz nesta aula

Esta seção existe para evitar a pergunta mais comum do autoestudo: *"por que o resto não está
no Terraform?"*. A resposta é que **os recursos não existem no provider** — não é uma escolha
didática.

| Etapa da aula | Existe resource Terraform? | Onde é feita então |
|---|---|---|
| Habilitar APIs | Sim — `google_project_service` | Terraform |
| Bucket de artefatos | Sim — `google_storage_bucket` | Terraform |
| Dataset BigQuery | Sim — `google_bigquery_dataset` | Terraform (com `import`) |
| IAM do projeto | Sim — `google_project_iam_member` | gcloud/console (bloco opcional no Passo 2) |
| **Experiment e runs** | **Não existe resource** | SDK Python (`aiplatform.init(experiment=...)`, `start_run()`) |
| **Registro do modelo treinado** | **Não existe `google_vertex_ai_model`** | SDK (`aiplatform.Model.upload`), `gcloud ai models upload` ou console |
| **Versões e aliases do modelo** | **Não existe resource** | SDK (`parent_model`, `version_aliases`) ou `gcloud ai models` |
| **Deploy do modelo no endpoint** | **Não existe resource** | SDK (`endpoint.deploy`) ou `gcloud ai endpoints deploy-model` |
| Endpoint (a "casca" vazia) | Sim — `google_vertex_ai_endpoint` | Fora do escopo deste material: o endpoint é criado junto com o deploy, no passo 04 |

Detalhamento dos pontos que mais confundem:

- **Não existe `google_vertex_ai_model`.** O provider `hashicorp/google` não tem um recurso
  para registrar um modelo treinado no Model Registry. O upload do artefato é imperativo por
  natureza (depende de um `model.joblib` que só existe depois do treino), então ele fica em
  SDK/gcloud/console. Recursos com nome parecido no provider tratam de outras coisas
  (por exemplo, `google_vertex_ai_endpoint`, `google_vertex_ai_tensorboard`).
- **Não existe resource para Vertex AI Experiments.** Nem em Terraform, nem em `gcloud`. O
  Experiment é criado implicitamente pelo SDK Python na primeira chamada de
  `aiplatform.init(..., experiment="preco-imoveis-rf")`. O único vizinho disponível em IaC é
  `google_vertex_ai_tensorboard` — que **não usamos**, porque é tarifado por armazenamento e as
  métricas-resumo desta aula não precisam dele. Atenção: esse `init` **cria uma instância
  *Default Tensorboard* sozinho** se você não passar `experiment_tensorboard=False` — o notebook
  da aula passa (veja `02-treino-e-experiments.md`).
- **Não existe resource para o deploy do *seu* modelo em um endpoint.** O
  `google_vertex_ai_endpoint` cria o endpoint vazio; associar uma versão de modelo a ele
  (`deployedModels`, tipo de máquina, réplicas) é feito por SDK/gcloud.
  Existe um recurso de nome parecido, `google_vertex_ai_endpoint_with_model_garden_deployment`,
  mas ele implanta **modelos do Model Garden** (catálogo do Google) — não um modelo seu vindo
  do Model Registry. `google_vertex_ai_deployment_resource_pool` também não serve: ele cria um
  *pool* de máquinas compartilhado, não o deployment.
- **`google_workbench_instance` existe**, caso a turma prefira Workbench ao BigQuery Studio.
  Atenção: o argumento é `location` e ele espera uma **zona** (`us-central1-a`), não a região.
  Não usamos Workbench nesta aula.

### Teardown e Terraform

`terraform destroy` **não** é o caminho de encerramento desta aula, por dois motivos:

1. Ele não remove o que mais custa — o **modelo implantado no endpoint**, que consome créditos por
   node-hora 24/7 mesmo sem tráfego —, porque esses recursos não estão sob Terraform.
2. Ele tentaria destruir o dataset `aula_pdm`, que é **infra compartilhada** (por isso o
   `prevent_destroy = true`, que faz o `destroy` falhar de propósito).

Use `bash scripts/30_teardown.sh`, que segue a ordem correta (do mais caro ao mais barato) e
**nunca** toca no bucket `SEU_PROJECT_ID-aula-pdm` nem no dataset `aula_pdm`. Se ainda assim
quiser remover o bucket da aula via Terraform depois do teardown, rode
`terraform destroy -target=google_storage_bucket.artefatos_aula`.

---

## Referências

- Habilitar APIs: <https://docs.cloud.google.com/apis/docs/getting-started>
- Papéis de IAM do Vertex AI: <https://docs.cloud.google.com/vertex-ai/docs/general/access-control>
- `gcloud projects add-iam-policy-binding`: <https://docs.cloud.google.com/sdk/gcloud/reference/projects/add-iam-policy-binding>
- `gcloud storage buckets create`: <https://docs.cloud.google.com/sdk/gcloud/reference/storage/buckets/create>
- Localização de datasets no BigQuery: <https://docs.cloud.google.com/bigquery/docs/locations>
- Containers pré-construídos de predição: <https://docs.cloud.google.com/vertex-ai/docs/predictions/pre-built-containers>
- Provider Terraform google: <https://registry.terraform.io/providers/hashicorp/google/latest/docs>
