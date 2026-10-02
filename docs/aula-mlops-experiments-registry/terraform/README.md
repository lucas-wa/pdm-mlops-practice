# Caminho Terraform — o setup como código

Provisiona **só a base** da aula: APIs, bucket de artefatos e dataset BigQuery. A aula ao vivo usa o
console; isto é **autoestudo**.

Experiments, registro de modelo e deploy **não têm recurso no provider** — veja
["O que o Terraform NÃO faz"](#o-que-o-terraform-não-faz).

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| [`versions.tf`](versions.tf) | `required_version >= 1.5`, provider `hashicorp/google ~> 6.0` |
| [`main.tf`](main.tf) | APIs, bucket `-mlops-aula`, dataset `aula_pdm` |
| [`variables.tf`](variables.tf) | `project_id`, `region`, `zone` |
| [`outputs.tf`](outputs.tf) | Bucket, `artifact_uri`, dataset e próximos passos |
| [`terraform.tfvars.example`](terraform.tfvars.example) | Modelo do `terraform.tfvars` |

## Como rodar

```bash
gcloud auth application-default login   # credenciais do provider google

cd docs/aula-mlops-experiments-registry/terraform
cp terraform.tfvars.example terraform.tfvars
# edite terraform.tfvars: troque SEU_PROJECT_ID pelo seu Project ID

terraform init
terraform plan
terraform apply
```

Não comite o `terraform.tfvars`. O Terraform **não** cria o projeto nem vincula faturamento: ambos são
pré-requisitos.

## O que ele provisiona

**APIs** (`google_project_service`) — `aiplatform`, `storage`, `bigquery`, `compute`. Para Workbench,
descomente `notebooks.googleapis.com` em `local.apis`.

```hcl
resource "google_project_service" "aula" {
  for_each = toset(local.apis)

  project = var.project_id
  service = each.value

  # Não desabilita a API no destroy: é ação de projeto inteiro e derrubaria
  # recursos de outras aulas.
  disable_on_destroy = false
}
```

**Bucket dedicado** (`google_storage_bucket`) — `${project_id}-mlops-aula`, `us-central1`, acesso
uniforme. O bucket compartilhado `-aula-pdm` **não é gerenciado aqui**.

```hcl
resource "google_storage_bucket" "artefatos_aula" {
  name     = local.bucket_name # "${var.project_id}-mlops-aula"
  project  = var.project_id
  location = var.region

  # force_destroy = true: aceitável porque este bucket é EXCLUSIVO da aula.
  force_destroy               = true
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  storage_class               = "STANDARD"

  depends_on = [google_project_service.aula]
}
```

**Dataset** (`google_bigquery_dataset`) — `aula_pdm`. **Ele normalmente já existe** desde as aulas
anteriores, e um `apply` sem importar falha com *Already Exists*:

```bash
terraform import google_bigquery_dataset.aula_pdm projects/SEU_PROJECT_ID/datasets/aula_pdm
```

```hcl
resource "google_bigquery_dataset" "aula_pdm" {
  dataset_id  = "aula_pdm"
  project     = var.project_id
  location    = var.region
  description = "Dados da disciplina PDM (camada gold)"

  delete_contents_on_destroy = false

  lifecycle {
    # Infra compartilhada: `terraform destroy` deve falhar em vez de apagar.
    prevent_destroy = true
  }

  depends_on = [google_project_service.aula]
}
```

**IAM é opcional e não está no `main.tf`**: cada aluno é `Owner` do próprio projeto, e `roles/owner` já
cobre tudo. Para um projeto compartilhado, acrescente:

```hcl
variable "iam_member" {
  description = "Principal que executa a aula (user:... ou serviceAccount:...)"
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

> **Nunca** use `google_project_iam_policy`: ele é **autoritativo** e substitui a política inteira do
> projeto, removendo bindings que não estiverem no seu código. Use `google_project_iam_member`, que é
> aditivo por principal+papel.

## O que o Terraform NÃO faz

Não é escolha didática: **os recursos não existem no provider**.

| Etapa | Recurso Terraform? | Onde é feita |
|---|---|---|
| Habilitar APIs | Sim — `google_project_service` | Terraform |
| Bucket de artefatos | Sim — `google_storage_bucket` | Terraform |
| Dataset BigQuery | Sim — `google_bigquery_dataset` | Terraform (com `import`) |
| IAM do projeto | Sim — `google_project_iam_member` | gcloud/console (bloco opcional acima) |
| **Experiment e runs** | **Não existe** | SDK Python (`aiplatform.init(experiment=...)`, `start_run()`) |
| **Registro do modelo** | **Não existe `google_vertex_ai_model`** | SDK (`Model.upload`), `gcloud ai models upload` ou console |
| **Versões e aliases** | **Não existe** | SDK (`parent_model`, `version_aliases`) ou `gcloud ai models` |
| **Deploy no endpoint** | **Não existe** | SDK (`endpoint.deploy`) ou `gcloud ai endpoints deploy-model` |
| Endpoint vazio | Sim — `google_vertex_ai_endpoint` | Fora do escopo: o endpoint é criado junto com o deploy |

Os três pontos que mais confundem:

- **Não existe `google_vertex_ai_model`.** O upload depende de um `model.joblib` que só existe depois do
  treino.
- **Não existe nada para Experiments** — nem em Terraform, nem em `gcloud`. O vizinho em IaC é
  `google_vertex_ai_tensorboard`, que **não usamos** (tarifado por armazenamento). Atenção:
  `aiplatform.init(..., experiment=...)` **cria uma instância *Default Tensorboard* sozinho** se você não
  passar `experiment_tensorboard=False` — o notebook da aula passa.
- **Não existe recurso para implantar o *seu* modelo.** `google_vertex_ai_endpoint` cria a casca vazia;
  associar uma versão a ela é SDK/gcloud. `google_vertex_ai_endpoint_with_model_garden_deployment`
  implanta modelos do **Model Garden**, não o seu, e `google_vertex_ai_deployment_resource_pool` cria um
  *pool* de máquinas, não o deployment.

`google_workbench_instance` existe, caso a turma prefira Workbench. O argumento é `location` e espera uma
**zona** (`us-central1-a`), não a região. Não usamos Workbench nesta aula.

## Teardown — não use `terraform destroy`

> **Consumo de créditos.** A turma usa **créditos educacionais** — não há cobrança no cartão de ninguém,
> mas os créditos são finitos. O **endpoint com modelo implantado é o maior consumidor**: node-hora,
> 24/7, mesmo sem tráfego.

`terraform destroy` **não** encerra a aula, por dois motivos:

1. Não remove o que mais custa — o **modelo implantado no endpoint** —, que não está sob Terraform.
2. Tentaria destruir o dataset `aula_pdm`, que é infra compartilhada (daí o `prevent_destroy = true`).

Use `bash gcloud/30_teardown.sh` ou o checklist de [`../05-encerramento-custos.md`](../05-encerramento-custos.md),
que seguem a ordem correta (undeploy → endpoint → modelo → artefatos) e **nunca** tocam no bucket
`-aula-pdm` nem no dataset `aula_pdm`.

Para remover o bucket da aula via Terraform **depois** do teardown:

```bash
terraform destroy -target=google_storage_bucket.artefatos_aula
```

---

Caminho imperativo: [`../gcloud/README.md`](../gcloud/README.md).
