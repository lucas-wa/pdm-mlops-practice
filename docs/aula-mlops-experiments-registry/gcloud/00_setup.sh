#!/usr/bin/env bash
#
# 00_setup.sh — prepara o projeto GCP para a aula de MLOps
# (Vertex AI Experiments + Model Registry + Endpoint).
#
# O que faz, de forma IDEMPOTENTE (pode rodar quantas vezes quiser):
#   1. habilita as APIs necessarias;
#   2. concede os papeis de IAM minimos ao principal informado;
#   3. cria o bucket DEDICADO da aula, se ainda nao existir;
#   4. confere o dataset BigQuery `aula_pdm` (cria apenas se estiver faltando).
#
# NESTA DISCIPLINA, CADA ALUNO E' OWNER DO PROPRIO PROJETO: roles/owner ja cobre
# tudo (Vertex AI, Storage, BigQuery, habilitar APIs), entao o passo 2 (IAM) e'
# REDUNDANTE e pode ser pulado com GRANT_IAM=false. O passo so faz sentido em
# projeto compartilhado ou com uma service account dedicada (menor privilegio).
#
# Uso:
#   PROJECT_ID=meu-projeto bash gcloud/00_setup.sh
#
#   # aluno Owner do proprio projeto (recomendado nesta disciplina):
#   PROJECT_ID=meu-projeto GRANT_IAM=false bash gcloud/00_setup.sh
#
# Variaveis de ambiente aceitas (todas opcionais, exceto PROJECT_ID):
#   PROJECT_ID     ID do projeto. Se ausente, usa `gcloud config get-value project`.
#   IAM_MEMBER     Principal que recebe os papeis, no formato
#                  "user:email@dominio.com" ou "serviceAccount:sa@projeto.iam.gserviceaccount.com".
#                  Se ausente, usa a conta ativa do gcloud.
#   GRANT_IAM      "true" (padrao) ou "false". Como voce e' Owner do projeto,
#                  use GRANT_IAM=false: roles/owner ja cobre tudo.
#   ENABLE_NOTEBOOKS_API  "false" (padrao). Use "true" APENAS se a turma
#                  usar Vertex AI Workbench (no BigQuery Studio nao e' preciso).
#
# NAO altera o bucket compartilhado ${PROJECT_ID}-aula-pdm nem apaga nada.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuracao (contrato de nomes da aula — nao altere sem alinhar com o resto
# do material: notebook, Terraform e 30_teardown.sh usam os mesmos nomes).
# ---------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${REGION:-us-central1}"

DATASET="aula_pdm"                         # dataset EXISTENTE (camada gold)
BUCKET="${PROJECT_ID}-mlops-aula"          # bucket NOVO e dedicado da aula
BUCKET_COMPARTILHADO="${PROJECT_ID}-aula-pdm"  # bucket de aulas anteriores: NAO TOCAR

GRANT_IAM="${GRANT_IAM:-true}"
ENABLE_NOTEBOOKS_API="${ENABLE_NOTEBOOKS_API:-false}"

APIS=(
  aiplatform.googleapis.com   # OBRIGATORIA: Experiments, Model Registry, Endpoints
  storage.googleapis.com      # artefato model.joblib
  bigquery.googleapis.com     # leitura da camada gold
  compute.googleapis.com      # maquinas do deploy no endpoint / runtime do notebook
)

PAPEIS=(
  roles/aiplatform.user       # criar runs, registrar modelo, criar endpoint, predizer
  roles/storage.objectAdmin   # escrever/ler model.joblib no bucket da aula
  roles/bigquery.dataViewer   # ler a tabela gold
  roles/bigquery.jobUser      # executar as queries
)

# ---------------------------------------------------------------------------
# Utilitarios
# ---------------------------------------------------------------------------
info()  { printf '\n[ %s ] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()    { printf '  OK   %s\n' "$*"; }
warn()  { printf '  AVISO %s\n' "$*" >&2; }
erro()  { printf '  ERRO %s\n' "$*" >&2; exit 1; }

command -v gcloud >/dev/null 2>&1 || erro "gcloud nao encontrado no PATH. Instale o Google Cloud SDK."
command -v bq     >/dev/null 2>&1 || erro "bq nao encontrado no PATH. Ele vem junto com o Google Cloud SDK."

[[ -n "${PROJECT_ID}" ]] || erro "PROJECT_ID vazio. Rode: PROJECT_ID=seu-projeto bash gcloud/00_setup.sh"
[[ "${PROJECT_ID}" != "SEU_PROJECT_ID" ]] || erro "Troque SEU_PROJECT_ID pelo ID real do seu projeto."

info "Configuracao"
printf '  Projeto ............ %s\n' "${PROJECT_ID}"
printf '  Regiao ............. %s\n' "${REGION}"
printf '  Dataset (existente)  %s\n' "${DATASET}"
printf '  Bucket da aula ..... gs://%s\n' "${BUCKET}"
printf '  Bucket compartilhado gs://%s (nao sera alterado)\n' "${BUCKET_COMPARTILHADO}"

# ---------------------------------------------------------------------------
# 1. APIs
# ---------------------------------------------------------------------------
info "1/4 Habilitando APIs"

if [[ "${ENABLE_NOTEBOOKS_API}" == "true" ]]; then
  APIS+=(notebooks.googleapis.com)   # somente para Vertex AI Workbench
fi

# `gcloud services enable` e' idempotente: reexecutar com API ja habilitada nao falha.
gcloud services enable "${APIS[@]}" --project="${PROJECT_ID}"
for api in "${APIS[@]}"; do
  ok "API habilitada: ${api}"
done

# ---------------------------------------------------------------------------
# 2. IAM
# ---------------------------------------------------------------------------
info "2/4 Concedendo papeis de IAM"

if [[ "${GRANT_IAM}" != "true" ]]; then
  warn "GRANT_IAM=${GRANT_IAM}: passo de IAM pulado."
else
  if [[ -z "${IAM_MEMBER:-}" ]]; then
    CONTA_ATIVA="$(gcloud config get-value account 2>/dev/null || true)"
    [[ -n "${CONTA_ATIVA}" ]] || erro "Nao foi possivel descobrir a conta ativa. Defina IAM_MEMBER."
    # Conta terminada em .gserviceaccount.com e' conta de servico.
    if [[ "${CONTA_ATIVA}" == *".gserviceaccount.com" ]]; then
      IAM_MEMBER="serviceAccount:${CONTA_ATIVA}"
    else
      IAM_MEMBER="user:${CONTA_ATIVA}"
    fi
    warn "IAM_MEMBER nao informado; usando a conta ativa: ${IAM_MEMBER}"
  fi

  printf '  Principal .......... %s\n' "${IAM_MEMBER}"
  for papel in "${PAPEIS[@]}"; do
    # add-iam-policy-binding e' idempotente e nao duplica bindings.
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="${IAM_MEMBER}" \
      --role="${papel}" \
      --condition=None \
      --quiet >/dev/null
    ok "Papel concedido: ${papel}"
  done
  printf '  Obs.: se o principal ja e Owner do projeto, estes papeis sao redundantes.\n'
fi

# ---------------------------------------------------------------------------
# 3. Bucket dedicado da aula
# ---------------------------------------------------------------------------
info "3/4 Bucket dedicado da aula"

if gcloud storage buckets describe "gs://${BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  ok "Bucket gs://${BUCKET} ja existe."
else
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --default-storage-class=STANDARD \
    --uniform-bucket-level-access \
    --public-access-prevention
  ok "Bucket gs://${BUCKET} criado em ${REGION}."
fi

printf '  Artefato do modelo ira para: gs://%s/models/rf/model.joblib\n' "${BUCKET}"
printf '  artifact_uri do Model Registry (DIRETORIO): gs://%s/models/rf/\n' "${BUCKET}"

# ---------------------------------------------------------------------------
# 4. Dataset BigQuery
# ---------------------------------------------------------------------------
info "4/4 Dataset BigQuery da camada gold"

if bq --project_id="${PROJECT_ID}" show --dataset "${PROJECT_ID}:${DATASET}" >/dev/null 2>&1; then
  LOCAL_DATASET="$(bq --project_id="${PROJECT_ID}" --format=prettyjson show \
    "${PROJECT_ID}:${DATASET}" 2>/dev/null | grep -m1 '"location"' | cut -d'"' -f4 || true)"
  ok "Dataset ${PROJECT_ID}:${DATASET} ja existe (location=${LOCAL_DATASET:-desconhecida})."
  # minusculas via tr (compativel com bash 3.x do macOS; ${var,,} exige bash 4+)
  LOCAL_LOWER="$(printf '%s' "${LOCAL_DATASET}" | tr '[:upper:]' '[:lower:]')"
  REGION_LOWER="$(printf '%s' "${REGION}" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "${LOCAL_DATASET}" && "${LOCAL_LOWER}" != "${REGION_LOWER}" ]]; then
    warn "Dataset em '${LOCAL_DATASET}', mas a aula usa '${REGION}'. Ajuste REGION para casar com o dataset."
  fi
else
  warn "Dataset ${PROJECT_ID}:${DATASET} nao encontrado. Criando em ${REGION}..."
  bq --project_id="${PROJECT_ID}" --location="${REGION}" mk \
    --dataset \
    --description="Camada gold de anuncios de imoveis (disciplina PDM)" \
    "${PROJECT_ID}:${DATASET}"
  ok "Dataset ${PROJECT_ID}:${DATASET} criado."
fi

printf '\n  Tabelas disponiveis no dataset (anote o nome real da gold -> GOLD_TABLE):\n'
bq --project_id="${PROJECT_ID}" ls "${PROJECT_ID}:${DATASET}" || \
  warn "Nao foi possivel listar as tabelas do dataset."

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
info "Setup concluido"
cat <<EOF
  Projeto ............. ${PROJECT_ID}
  Regiao .............. ${REGION}
  Bucket da aula ...... gs://${BUCKET}
  Dataset ............. ${PROJECT_ID}:${DATASET}
  Experiment .......... preco-imoveis-rf        (criado pelo SDK no notebook)
  Modelo .............. rf-preco-imoveis        (registrado pelo SDK/gcloud)
  Endpoint ............ rf-preco-imoveis-endpoint (criado no passo de deploy)

  Proximo passo: abrir o notebook da aula no BigQuery Studio.
  Ao terminar, rode \`bash gcloud/30_teardown.sh\` para nao deixar o endpoint
  consumindo creditos por node-hora 24/7, mesmo sem trafego.
EOF
