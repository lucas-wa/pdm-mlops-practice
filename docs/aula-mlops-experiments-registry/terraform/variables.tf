variable "project_id" {
  description = "ID do projeto GCP onde a aula sera executada (ex.: SEU_PROJECT_ID)."
  type        = string

  validation {
    condition     = length(trimspace(var.project_id)) > 0 && var.project_id != "SEU_PROJECT_ID"
    error_message = "Defina project_id com o ID real do seu projeto (veja terraform.tfvars.example)."
  }
}

variable "region" {
  description = "Regiao dos recursos da aula. Precisa casar com a regiao do dataset BigQuery."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona usada por recursos que exigem zona (ex.: google_workbench_instance). Nao usada nesta aula."
  type        = string
  default     = "us-central1-a"
}
