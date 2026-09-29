#!/usr/bin/env bash
#
# 20_deploy_endpoint.sh — cria o endpoint, deploya o modelo e faz uma predição.
#
# Espelha os comandos gcloud de ../04-deploy-endpoint.md.
# Pré-requisito: o modelo já registrado (./10_register_model.sh ou a seção 7 do notebook).
#
# É idempotente: reaproveita o endpoint se ele já existir e pula o deploy se o
# modelo já estiver servido ali.
#
# >>> ATENÇÃO — CUSTO <<<
# Um modelo deployado cobra POR NODE-HORA, 24h por dia, MESMO SEM TRÁFEGO, e o
# endpoint não desliga sozinho. Ao terminar, rode o teardown de
# ../05-encerramento-custos.md (undeploy -> delete endpoint -> delete model).
#
# Uso:
#   ./20_deploy_endpoint.sh
#   PROJECT_ID=meu-projeto ./20_deploy_endpoint.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Variáveis — ajuste aqui (ou exporte antes de chamar o script)
# ---------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-us-central1}"

MODEL_DISPLAY_NAME="${MODEL_DISPLAY_NAME:-rf-preco-imoveis}"
ENDPOINT_DISPLAY_NAME="${ENDPOINT_DISPLAY_NAME:-rf-preco-imoveis-endpoint}"

MACHINE_TYPE="${MACHINE_TYPE:-n1-standard-2}"
MIN_REPLICAS="${MIN_REPLICAS:-1}"
MAX_REPLICAS="${MAX_REPLICAS:-1}"

REQUEST_JSON="${REQUEST_JSON:-request.json}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "ERRO: defina PROJECT_ID (export PROJECT_ID=SEU_PROJECT_ID) ou rode 'gcloud config set project'." >&2
  exit 1
fi

echo "projeto  : ${PROJECT_ID}"
echo "regiao   : ${REGION}"
echo "modelo   : ${MODEL_DISPLAY_NAME}"
echo "endpoint : ${ENDPOINT_DISPLAY_NAME}"
echo

# ---------------------------------------------------------------------------
# 1. Localizar o modelo registrado
# ---------------------------------------------------------------------------
echo "==> Procurando '${MODEL_DISPLAY_NAME}' no Model Registry"
MODEL_RESOURCE="$(gcloud ai models list \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --filter="displayName=${MODEL_DISPLAY_NAME}" \
  --format='value(name)' \
  --limit=1)"

if [[ -z "${MODEL_RESOURCE}" ]]; then
  echo "ERRO: modelo '${MODEL_DISPLAY_NAME}' não encontrado em ${REGION}." >&2
  echo "      Rode ./10_register_model.sh antes." >&2
  exit 1
fi

MODEL_ID="${MODEL_RESOURCE##*/}"
echo "    MODEL_ID=${MODEL_ID}"
echo

# ---------------------------------------------------------------------------
# 2. Endpoint: criar se não existir
# ---------------------------------------------------------------------------
echo "==> Procurando o endpoint '${ENDPOINT_DISPLAY_NAME}'"
ENDPOINT_RESOURCE="$(gcloud ai endpoints list \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --filter="displayName=${ENDPOINT_DISPLAY_NAME}" \
  --format='value(name)' \
  --limit=1)"

if [[ -z "${ENDPOINT_RESOURCE}" ]]; then
  echo "    não existe — criando"
  gcloud ai endpoints create \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --display-name="${ENDPOINT_DISPLAY_NAME}"

  ENDPOINT_RESOURCE="$(gcloud ai endpoints list \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --filter="displayName=${ENDPOINT_DISPLAY_NAME}" \
    --format='value(name)' \
    --limit=1)"
else
  echo "    já existe — reaproveitando"
fi

ENDPOINT_ID="${ENDPOINT_RESOURCE##*/}"
echo "    ENDPOINT_ID=${ENDPOINT_ID}"
echo

# ---------------------------------------------------------------------------
# 3. Deploy — só se o modelo ainda não estiver servido neste endpoint
# ---------------------------------------------------------------------------
echo "==> Conferindo o que já está deployado"
DEPLOYED="$(gcloud ai endpoints describe "${ENDPOINT_ID}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --format="value(deployedModels[].model)")"

if [[ "${DEPLOYED}" == *"/models/${MODEL_ID}"* ]]; then
  echo "    o modelo ${MODEL_ID} já está servido neste endpoint — pulando o deploy"
else
  echo "    deployando ${MODEL_ID} em ${ENDPOINT_ID}"
  echo "    >>> isto leva de 10 a 20 minutos e INICIA A COBRANÇA por node-hora <<<"
  gcloud ai endpoints deploy-model "${ENDPOINT_ID}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --model="${MODEL_ID}" \
    --display-name="${MODEL_DISPLAY_NAME}" \
    --machine-type="${MACHINE_TYPE}" \
    --min-replica-count="${MIN_REPLICAS}" \
    --max-replica-count="${MAX_REPLICAS}" \
    --traffic-split=0=100
fi
echo

# ---------------------------------------------------------------------------
# 4. Predição de teste
#
# ORDEM CANÔNICA DO VETOR DE FEATURES (posicional, sem nomes de coluna):
#   [area_util, area_total, quartos, banheiros, garagens]
# ---------------------------------------------------------------------------
if [[ ! -f "${REQUEST_JSON}" ]]; then
  echo "==> Gerando ${REQUEST_JSON}"
  cat > "${REQUEST_JSON}" <<'JSON'
{
  "instances": [
    [120.0, 150.0, 3, 2, 1],
    [45.0, 55.0, 1, 1, 0]
  ]
}
JSON
fi

echo "==> Predição de teste ([area_util, area_total, quartos, banheiros, garagens])"
cat "${REQUEST_JSON}"
gcloud ai endpoints predict "${ENDPOINT_ID}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --json-request="${REQUEST_JSON}"
echo

# ---------------------------------------------------------------------------
# 5. Lembrete de teardown
# ---------------------------------------------------------------------------
DEPLOYED_MODEL_ID="$(gcloud ai endpoints describe "${ENDPOINT_ID}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --format="value(deployedModels[0].id)")"

cat <<EOF
=============================================================================
 O ENDPOINT ESTÁ LIGADO E COBRANDO POR NODE-HORA, 24h POR DIA.
 Ao terminar a aula, rode nesta ordem (veja ../05-encerramento-custos.md):

   gcloud ai endpoints undeploy-model ${ENDPOINT_ID} \\
     --region=${REGION} --deployed-model-id=${DEPLOYED_MODEL_ID}

   gcloud ai endpoints delete ${ENDPOINT_ID} --region=${REGION}

   gcloud ai models delete ${MODEL_ID} --region=${REGION}

 Não dá para deletar um modelo que ainda está deployado — a ordem importa.
=============================================================================
EOF
