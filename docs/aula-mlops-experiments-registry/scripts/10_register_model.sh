#!/usr/bin/env bash
#
# 10_register_model.sh — registra o modelo treinado no Vertex AI Model Registry.
#
# Espelha os comandos gcloud de ../03-model-registry.md.
# Pré-requisito: o arquivo model.joblib já existe em gs://${BUCKET}/models/rf/
#                (a seção 6 do notebook faz esse upload).
#
# É idempotente: se o modelo já existir, o script cria uma NOVA VERSÃO
# (--parent-model) em vez de um segundo modelo com o mesmo nome.
#
# Uso:
#   ./10_register_model.sh
#   PROJECT_ID=meu-projeto ./10_register_model.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Variáveis — ajuste aqui (ou exporte antes de chamar o script)
# ---------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-us-central1}"
BUCKET="${BUCKET:-${PROJECT_ID}-mlops-aula}"

# O artifact_uri aponta para o DIRETÓRIO, não para o arquivo. O arquivo lá dentro
# precisa se chamar exatamente model.joblib.
ARTIFACT_URI="${ARTIFACT_URI:-gs://${BUCKET}/models/rf/}"

MODEL_DISPLAY_NAME="${MODEL_DISPLAY_NAME:-rf-preco-imoveis}"
SERVING_CONTAINER="${SERVING_CONTAINER:-us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest}"
VERSION_ALIAS="${VERSION_ALIAS:-campeao}"

# Ordem canônica do vetor de features servido por este modelo:
#   [area_util, area_total, quartos, banheiros, garagens]

if [[ -z "${PROJECT_ID}" ]]; then
  echo "ERRO: defina PROJECT_ID (export PROJECT_ID=SEU_PROJECT_ID) ou rode 'gcloud config set project'." >&2
  exit 1
fi

echo "projeto  : ${PROJECT_ID}"
echo "regiao   : ${REGION}"
echo "artefato : ${ARTIFACT_URI}"
echo "modelo   : ${MODEL_DISPLAY_NAME}"
echo

# ---------------------------------------------------------------------------
# 1. Conferir que o artefato está no lugar certo, com o nome certo
# ---------------------------------------------------------------------------
echo "==> Conferindo o artefato em ${ARTIFACT_URI}model.joblib"
if ! gcloud storage ls "${ARTIFACT_URI}model.joblib" >/dev/null 2>&1; then
  echo "ERRO: ${ARTIFACT_URI}model.joblib não encontrado." >&2
  echo "      O container sklearn procura um arquivo chamado exatamente 'model.joblib'." >&2
  echo "      Rode a seção 6 do notebook ou: gcloud storage cp model.joblib ${ARTIFACT_URI}model.joblib" >&2
  exit 1
fi
echo "    ok"
echo

# ---------------------------------------------------------------------------
# 2. O modelo já existe no Registry?
# ---------------------------------------------------------------------------
echo "==> Procurando '${MODEL_DISPLAY_NAME}' no Model Registry"
MODEL_RESOURCE="$(gcloud ai models list \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --filter="displayName=${MODEL_DISPLAY_NAME}" \
  --format='value(name)' \
  --limit=1)"

# ---------------------------------------------------------------------------
# 3. Upload: v1 (modelo novo) ou nova versão (--parent-model)
# ---------------------------------------------------------------------------
if [[ -z "${MODEL_RESOURCE}" ]]; then
  echo "    não existe — criando a versão 1"
  echo
  echo "==> gcloud ai models upload (v1)"
  gcloud ai models upload \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --display-name="${MODEL_DISPLAY_NAME}" \
    --artifact-uri="${ARTIFACT_URI}" \
    --container-image-uri="${SERVING_CONTAINER}" \
    --description="RandomForest para preço de anúncio a partir da gold de imóveis."
else
  MODEL_ID="${MODEL_RESOURCE##*/}"
  echo "    encontrado (id ${MODEL_ID}) — criando uma NOVA VERSÃO"
  echo
  echo "==> gcloud ai models upload (nova versão, --parent-model)"
  gcloud ai models upload \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --display-name="${MODEL_DISPLAY_NAME}" \
    --parent-model="${MODEL_ID}" \
    --artifact-uri="${ARTIFACT_URI}" \
    --container-image-uri="${SERVING_CONTAINER}" \
    --version-aliases="${VERSION_ALIAS}" \
    --version-description="Retreino registrado por 10_register_model.sh."
fi
echo

# ---------------------------------------------------------------------------
# 4. Conferir o resultado
# ---------------------------------------------------------------------------
MODEL_RESOURCE="$(gcloud ai models list \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --filter="displayName=${MODEL_DISPLAY_NAME}" \
  --format='value(name)' \
  --limit=1)"
MODEL_ID="${MODEL_RESOURCE##*/}"

echo "==> Versões de ${MODEL_DISPLAY_NAME} (id ${MODEL_ID})"
gcloud ai models list-version "${MODEL_ID}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}"
echo

echo "Pronto. MODEL_ID=${MODEL_ID}"
echo "Próximo passo: ./20_deploy_endpoint.sh (ATENÇÃO: o endpoint gera custo por node-hora)."
echo
echo "Para apagar depois (veja ../05-encerramento-custos.md):"
echo "  gcloud ai models delete-version ${MODEL_ID}@2 --region=${REGION}"
echo "  gcloud ai models delete ${MODEL_ID} --region=${REGION}"
