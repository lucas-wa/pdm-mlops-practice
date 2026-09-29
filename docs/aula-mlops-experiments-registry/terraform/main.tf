###############################################################################
# Setup da aula "MLOps no GCP: Experiments + Model Registry + Endpoint".
#
# ESCOPO deste Terraform (o que ele provisiona):
#   - APIs do projeto
#   - Bucket DEDICADO de artefatos da aula: ${project_id}-mlops-aula
#   - Dataset BigQuery `aula_pdm` (normalmente ja existe -> use `terraform import`)
#
# FORA DO ESCOPO (nao existe recurso no provider hashicorp/google):
#   - Vertex AI Experiments e runs  -> SDK Python (aiplatform.init(experiment=...))
#   - Registro do modelo treinado   -> NAO existe `google_vertex_ai_model`;
#                                      use SDK (aiplatform.Model.upload),
#                                      `gcloud ai models upload` ou o console
#   - Versoes e aliases do modelo   -> SDK / gcloud
#   - Deploy do modelo no endpoint  -> SDK (endpoint.deploy) / gcloud
#                                      (`google_vertex_ai_endpoint` cria apenas a
#                                       casca vazia do endpoint; associar uma
#                                       versao de modelo a ele nao e' possivel
#                                       em Terraform)
# Detalhamento em ../01-setup-gcp.md, secao "O que o Terraform NAO faz".
#
# TEARDOWN: `terraform destroy` NAO e' o caminho de encerramento da aula.
# Ele nao remove o que mais custa (modelo implantado no endpoint, cobrado por
# node-hora 24/7). Use `bash ../scripts/30_teardown.sh`.
###############################################################################

locals {
  # APIs habilitadas para a aula.
  apis = [
    "aiplatform.googleapis.com", # OBRIGATORIA: Experiments, Model Registry, Endpoints
    "storage.googleapis.com",    # artefato model.joblib
    "bigquery.googleapis.com",   # leitura da camada gold
    "compute.googleapis.com",    # maquinas do deploy no endpoint / runtime do notebook

    # Descomente APENAS se a turma usar Vertex AI Workbench.
    # No BigQuery Studio esta API nao e' necessaria.
    # "notebooks.googleapis.com",
  ]

  # Bucket NOVO e DEDICADO da aula. Nao confundir com o bucket compartilhado
  # `${var.project_id}-aula-pdm`, das aulas anteriores, que NAO e' gerenciado aqui.
  bucket_name = "${var.project_id}-mlops-aula"

  # Dataset da camada gold (aulas anteriores).
  dataset_id = "aula_pdm"
}

###############################################################################
# 1. APIs
###############################################################################

resource "google_project_service" "aula" {
  for_each = toset(local.apis)

  project = var.project_id
  service = each.value

  # Nao desabilitar a API no destroy: desabilitar e' uma acao de projeto inteiro
  # e derrubaria recursos de outras aulas que dependem da mesma API.
  disable_on_destroy = false

  # Nao desabilitar servicos dependentes junto.
  disable_dependent_services = false
}

###############################################################################
# 2. Bucket dedicado de artefatos da aula
#
# O artefato do modelo vai para:
#   gs://${var.project_id}-mlops-aula/models/rf/model.joblib
# e o Model Registry aponta para o DIRETORIO gs://.../models/rf/ .
###############################################################################

resource "google_storage_bucket" "artefatos_aula" {
  name     = local.bucket_name
  project  = var.project_id
  location = var.region

  # force_destroy = true permite apagar o bucket mesmo com objetos dentro.
  # E' aceitavel porque este bucket e' EXCLUSIVO da aula e descartavel.
  force_destroy = true

  # Acesso uniforme por bucket (sem ACLs por objeto).
  uniform_bucket_level_access = true

  public_access_prevention = "enforced"
  storage_class            = "STANDARD"

  labels = {
    disciplina = "pdm"
    aula       = "mlops-experiments-registry"
  }

  depends_on = [google_project_service.aula]
}

###############################################################################
# 3. Dataset BigQuery da camada gold
#
# ATENCAO: este dataset normalmente JA EXISTE desde as aulas anteriores.
# Um `terraform apply` sem importar falha com "Already Exists". Importe antes:
#
#   terraform import google_bigquery_dataset.aula_pdm \
#     projects/SEU_PROJECT_ID/datasets/aula_pdm
#
# Se preferir nao gerenciar o dataset por Terraform, comente este bloco inteiro:
# nada mais neste arquivo depende dele.
###############################################################################

resource "google_bigquery_dataset" "aula_pdm" {
  dataset_id    = local.dataset_id
  project       = var.project_id
  location      = var.region
  friendly_name = "Dados da disciplina PDM"
  description   = "Camada gold de anuncios de imoveis (aulas anteriores da disciplina PDM)."

  # NUNCA apagar as tabelas junto com o dataset.
  delete_contents_on_destroy = false

  lifecycle {
    # Infra COMPARTILHADA de aulas anteriores: um `terraform destroy` deve
    # falhar de proposito em vez de apagar os dados da turma.
    # Para remover a protecao (nao recomendado), apague este bloco; para so
    # tirar o dataset do controle do Terraform sem apaga-lo, use:
    #   terraform state rm google_bigquery_dataset.aula_pdm
    prevent_destroy = true
  }

  depends_on = [google_project_service.aula]
}
