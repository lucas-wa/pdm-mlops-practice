output "project_id" {
  description = "Projeto GCP usado na aula."
  value       = var.project_id
}

output "region" {
  description = "Regiao dos recursos da aula."
  value       = var.region
}

output "apis_habilitadas" {
  description = "APIs habilitadas por este Terraform."
  value       = sort([for s in google_project_service.aula : s.service])
}

output "bucket_aula" {
  description = "Nome do bucket dedicado de artefatos da aula."
  value       = google_storage_bucket.artefatos_aula.name
}

output "bucket_aula_uri" {
  description = "URI gs:// do bucket dedicado da aula."
  value       = "gs://${google_storage_bucket.artefatos_aula.name}"
}

output "model_artifact_dir" {
  description = "Diretorio GCS do artefato: valor do artifact_uri no Model Registry."
  value       = "gs://${google_storage_bucket.artefatos_aula.name}/models/rf/"
}

output "model_artifact_file" {
  description = "Caminho exato do artefato. O arquivo PRECISA se chamar model.joblib."
  value       = "gs://${google_storage_bucket.artefatos_aula.name}/models/rf/model.joblib"
}

output "dataset_id" {
  description = "Dataset BigQuery da camada gold."
  value       = google_bigquery_dataset.aula_pdm.dataset_id
}

output "proximos_passos" {
  description = "O que NAO e' feito por Terraform e precisa ser feito por SDK/gcloud/console."
  value = join("\n", [
    "Experiment 'preco-imoveis-rf': criado pelo SDK em aiplatform.init(experiment=...).",
    "Modelo 'rf-preco-imoveis': registrado por aiplatform.Model.upload / gcloud ai models upload.",
    "Endpoint 'rf-preco-imoveis-endpoint': criado e alimentado por SDK / gcloud ai endpoints deploy-model.",
    "Encerramento: bash ../scripts/30_teardown.sh (NAO use terraform destroy).",
  ])
}
