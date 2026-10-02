#!/usr/bin/env bash
#
# 30_teardown.sh — encerra TODOS os recursos criados nesta aula, na ordem
# correta (do mais caro ao mais barato), de forma IDEMPOTENTE.
#
# Rode este script ao final da aula. O item 1 e' o que mais consome creditos:
# um modelo implantado em endpoint consome por node-hora 24/7, MESMO SEM TRAFEGO.
#
# Ordem executada:
#   1. undeploy do(s) modelo(s) no endpoint  -> depois delete do endpoint
#   2. runtime do notebook (BigQuery Studio / Colab Enterprise / Workbench)
#   3. instancia de TensorBoard, se existir   (a aula nao cria SE experiment_tensorboard=False;
#                                              verificamos por seguranca; ver DELETE_TENSORBOARD)
#   4. versoes e modelo no Model Registry
#   5. objetos e bucket DEDICADO da aula no Cloud Storage
#
# ############################################################################
# # PROTECAO DE INFRA COMPARTILHADA                                          #
# # Este script NUNCA apaga:                                                 #
# #   - o bucket  gs://${PROJECT_ID}-aula-pdm   (aulas anteriores)           #
# #   - o dataset ${PROJECT_ID}:aula_pdm        (camada gold da turma)       #
# # Apaga apenas o bucket DEDICADO gs://${PROJECT_ID}-mlops-aula.            #
# # Nao remova as checagens abaixo.                                          #
# ############################################################################
#
# Uso:
#   PROJECT_ID=meu-projeto bash scripts/30_teardown.sh
#
# Variaveis de ambiente aceitas:
#   PROJECT_ID          ID do projeto. Se ausente, usa `gcloud config get-value project`.
#   REGION              Padrao us-central1.
#   ZONE                Padrao us-central1-a (usada so para procurar Workbench).
#   DELETE_BUCKET       "true" (padrao): apaga o bucket dedicado da aula.
#                       "false": apaga so os objetos em models/rf/ e mantem o bucket.
#   DELETE_TENSORBOARD  "false" (padrao). A aula nao cria TensorBoard SE o aiplatform.init(...)
#                       passar experiment_tensorboard=False; sem esse parametro o SDK cria uma
#                       instancia Default Tensorboard sozinho. Verificamos por seguranca: se houver
#                       instancias no projeto, elas podem ser de outra atividade.
#                       Use "true" so se tiver certeza de que sao suas.
#   DRY_RUN             "true" mostra o que seria removido, sem remover nada.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuracao (contrato de nomes da aula)
# ---------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"

MODEL_DISPLAY_NAME="rf-preco-imoveis"
ENDPOINT_DISPLAY_NAME="rf-preco-imoveis-endpoint"

BUCKET="${PROJECT_ID}-mlops-aula"              # bucket DEDICADO da aula (removivel)
BUCKET_COMPARTILHADO="${PROJECT_ID}-aula-pdm"  # bucket de aulas anteriores: PROTEGIDO
DATASET_COMPARTILHADO="aula_pdm"               # dataset da camada gold: PROTEGIDO

DELETE_BUCKET="${DELETE_BUCKET:-true}"
DELETE_TENSORBOARD="${DELETE_TENSORBOARD:-false}"
DRY_RUN="${DRY_RUN:-false}"

# ---------------------------------------------------------------------------
# Utilitarios
# ---------------------------------------------------------------------------
info()  { printf '\n[ %s ] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()    { printf '  OK    %s\n' "$*"; }
skip()  { printf '  PULA  %s\n' "$*"; }
warn()  { printf '  AVISO %s\n' "$*" >&2; }
erro()  { printf '  ERRO  %s\n' "$*" >&2; exit 1; }

# Executa o comando, ou apenas imprime se DRY_RUN=true.
# Nunca interrompe o script: um recurso ja removido nao e' erro.
run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '  [DRY_RUN] %s\n' "$*"
    return 0
  fi
  printf '  -> %s\n' "$*"
  if "$@"; then
    return 0
  else
    warn "comando falhou (recurso ja removido ou sem permissao): $*"
    return 0
  fi
}

command -v gcloud >/dev/null 2>&1 || erro "gcloud nao encontrado no PATH."
[[ -n "${PROJECT_ID}" ]] || erro "PROJECT_ID vazio. Rode: PROJECT_ID=seu-projeto bash scripts/30_teardown.sh"
[[ "${PROJECT_ID}" != "SEU_PROJECT_ID" ]] || erro "Troque SEU_PROJECT_ID pelo ID real do seu projeto."

# Trava de seguranca: o bucket a remover jamais pode ser o compartilhado.
if [[ "${BUCKET}" == "${BUCKET_COMPARTILHADO}" ]]; then
  erro "Recusando: o bucket da aula coincide com o bucket compartilhado (${BUCKET})."
fi

info "Encerramento dos recursos da aula"
printf '  Projeto ............ %s\n' "${PROJECT_ID}"
printf '  Regiao ............. %s\n' "${REGION}"
printf '  Endpoint ........... %s\n' "${ENDPOINT_DISPLAY_NAME}"
printf '  Modelo ............. %s\n' "${MODEL_DISPLAY_NAME}"
printf '  Bucket a remover ... gs://%s\n' "${BUCKET}"
printf '  PROTEGIDOS ......... gs://%s e dataset %s (NAO serao tocados)\n' \
  "${BUCKET_COMPARTILHADO}" "${DATASET_COMPARTILHADO}"
# `|| true` e' obrigatorio: sob `set -e`, um `[[ ]] && cmd` que falha encerraria o script.
[[ "${DRY_RUN}" == "true" ]] && warn "DRY_RUN=true: nada sera removido de fato." || true

# ---------------------------------------------------------------------------
# 1. Endpoint: undeploy do modelo e delete do endpoint  (MAIOR CUSTO)
# ---------------------------------------------------------------------------
info "1/5 Endpoint de predicao online (maior custo: node-hora 24/7)"

ENDPOINT_IDS="$(gcloud ai endpoints list \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --filter="displayName=${ENDPOINT_DISPLAY_NAME}" \
  --format="value(name)" 2>/dev/null || true)"

if [[ -z "${ENDPOINT_IDS}" ]]; then
  skip "Nenhum endpoint '${ENDPOINT_DISPLAY_NAME}' encontrado em ${REGION}."
else
  while IFS= read -r ENDPOINT_PATH; do
    [[ -n "${ENDPOINT_PATH}" ]] || continue
    ENDPOINT_ID="${ENDPOINT_PATH##*/}"   # so o ID numerico
    printf '  Endpoint encontrado: %s\n' "${ENDPOINT_ID}"

    # 1a. undeploy de cada modelo implantado (obrigatorio antes de deletar o modelo)
    DEPLOYED_IDS="$(gcloud ai endpoints describe "${ENDPOINT_ID}" \
      --region="${REGION}" \
      --project="${PROJECT_ID}" \
      --flatten="deployedModels[]" \
      --format="value(deployedModels.id)" 2>/dev/null || true)"

    if [[ -z "${DEPLOYED_IDS}" ]]; then
      skip "Endpoint ${ENDPOINT_ID} nao tem modelo implantado."
    else
      while IFS= read -r DEPLOYED_ID; do
        [[ -n "${DEPLOYED_ID}" ]] || continue
        printf '  Removendo deployment %s do endpoint %s...\n' "${DEPLOYED_ID}" "${ENDPOINT_ID}"
        run gcloud ai endpoints undeploy-model "${ENDPOINT_ID}" \
          --region="${REGION}" \
          --project="${PROJECT_ID}" \
          --deployed-model-id="${DEPLOYED_ID}" \
          --quiet
      done <<< "${DEPLOYED_IDS}"
      ok "Modelos retirados do endpoint ${ENDPOINT_ID} (cobranca por node-hora encerrada)."
    fi

    # 1b. deletar o endpoint (so e' possivel sem deployments)
    printf '  Deletando endpoint %s...\n' "${ENDPOINT_ID}"
    run gcloud ai endpoints delete "${ENDPOINT_ID}" \
      --region="${REGION}" \
      --project="${PROJECT_ID}" \
      --quiet
    ok "Endpoint ${ENDPOINT_ID} removido."
  done <<< "${ENDPOINT_IDS}"
fi

# ---------------------------------------------------------------------------
# 2. Runtime do notebook
# ---------------------------------------------------------------------------
info "2/5 Runtime do notebook"

cat <<'EOF'
  BigQuery Studio / Colab Enterprise: o runtime NAO e' removido por este script.
  Encerre pelo console:
    BigQuery > Notebooks (ou Colab Enterprise > Runtimes) > selecione o runtime
    > Stop, e em seguida Delete.
  O runtime tem auto-shutdown por inatividade (~180 min), mas ate' la ele cobra.
EOF

# Vertex AI Workbench (so se a turma tiver usado). O grupo de comandos pode nao
# existir ou a API estar desabilitada: tolerar falha.
WORKBENCH="$(gcloud workbench instances list \
  --location="${ZONE}" \
  --project="${PROJECT_ID}" \
  --format="value(name)" 2>/dev/null || true)"

if [[ -z "${WORKBENCH}" ]]; then
  skip "Nenhuma instancia do Vertex AI Workbench encontrada em ${ZONE}."
else
  warn "Instancias do Workbench encontradas em ${ZONE}:"
  printf '%s\n' "${WORKBENCH}" | sed 's/^/        /'
  warn "Elas podem ser de outra atividade. Remova manualmente se forem suas:"
  printf '        gcloud workbench instances delete NOME --location=%s --project=%s\n' \
    "${ZONE}" "${PROJECT_ID}"
fi

# ---------------------------------------------------------------------------
# 3. TensorBoard (a aula nao cria SE experiment_tensorboard=False; verificamos por seguranca,
#    porque sem esse parametro o SDK cria uma instancia sozinho. Cobranca por armazenamento.)
# ---------------------------------------------------------------------------
info "3/5 Instancias de TensorBoard"

TENSORBOARDS="$(gcloud ai tensorboards list \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(name)" 2>/dev/null || true)"

if [[ -z "${TENSORBOARDS}" ]]; then
  skip "Nenhuma instancia de TensorBoard em ${REGION} (esperado com experiment_tensorboard=False)."
elif [[ "${DELETE_TENSORBOARD}" != "true" ]]; then
  warn "Instancias de TensorBoard encontradas (cobram por armazenamento):"
  printf '%s\n' "${TENSORBOARDS}" | sed 's/^/        /'
  warn "Podem ser de outra atividade, por isso NAO foram removidas."
  warn "Se forem suas, rode de novo com: DELETE_TENSORBOARD=true"
else
  while IFS= read -r TB_PATH; do
    [[ -n "${TB_PATH}" ]] || continue
    TB_ID="${TB_PATH##*/}"
    printf '  Deletando TensorBoard %s...\n' "${TB_ID}"
    run gcloud ai tensorboards delete "${TB_ID}" \
      --region="${REGION}" \
      --project="${PROJECT_ID}" \
      --quiet
  done <<< "${TENSORBOARDS}"
  ok "TensorBoards removidos."
fi

# ---------------------------------------------------------------------------
# 4. Model Registry: versoes e modelo
# ---------------------------------------------------------------------------
info "4/5 Model Registry"

MODEL_IDS="$(gcloud ai models list \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --filter="displayName=${MODEL_DISPLAY_NAME}" \
  --format="value(name)" 2>/dev/null || true)"

if [[ -z "${MODEL_IDS}" ]]; then
  skip "Nenhum modelo '${MODEL_DISPLAY_NAME}' encontrado em ${REGION}."
else
  # `gcloud ai models list` pode repetir o mesmo modelo uma vez por versao.
  MODEL_IDS="$(printf '%s\n' "${MODEL_IDS}" | awk -F/ 'NF{print $NF}' | sort -u)"

  while IFS= read -r MODEL_ID; do
    [[ -n "${MODEL_ID}" ]] || continue
    printf '  Modelo encontrado: %s\n' "${MODEL_ID}"

    # 4a. apagar as versoes NAO-default primeiro: o modelo so pode ser deletado
    #     quando resta apenas a versao default.
    VERSOES="$(gcloud ai models list-version "${MODEL_ID}" \
      --region="${REGION}" \
      --project="${PROJECT_ID}" \
      --format="value(versionId,versionAliases)" 2>/dev/null || true)"

    if [[ -n "${VERSOES}" ]]; then
      while IFS= read -r LINHA; do
        [[ -n "${LINHA}" ]] || continue
        VERSION_ID="$(printf '%s' "${LINHA}" | awk '{print $1}')"
        ALIASES="$(printf '%s' "${LINHA}" | cut -f2- 2>/dev/null || true)"
        [[ -n "${VERSION_ID}" ]] || continue
        if printf '%s' "${ALIASES}" | grep -q 'default'; then
          skip "Versao ${VERSION_ID} e' a default; sera removida junto com o modelo."
          continue
        fi
        printf '  Deletando versao %s@%s...\n' "${MODEL_ID}" "${VERSION_ID}"
        run gcloud ai models delete-version "${MODEL_ID}@${VERSION_ID}" \
          --region="${REGION}" \
          --project="${PROJECT_ID}" \
          --quiet
      done <<< "${VERSOES}"
    fi

    # 4b. apagar o modelo (com a versao default restante)
    printf '  Deletando modelo %s...\n' "${MODEL_ID}"
    run gcloud ai models delete "${MODEL_ID}" \
      --region="${REGION}" \
      --project="${PROJECT_ID}" \
      --quiet
    ok "Modelo ${MODEL_ID} removido."
  done <<< "${MODEL_IDS}"
fi

# Experiments: nao ha comando gcloud. Remover pelo console, se desejar.
cat <<EOF

  Vertex AI Experiments: nao tem comando gcloud e NAO gera custo
  (metricas-resumo, sem TensorBoard - init com experiment_tensorboard=False).
  Se quiser limpar o historico:
    console > Vertex AI > Experiments > preco-imoveis-rf > Delete.
EOF

# ---------------------------------------------------------------------------
# 5. Cloud Storage: objetos e bucket DEDICADO da aula
# ---------------------------------------------------------------------------
info "5/5 Cloud Storage (apenas o bucket dedicado da aula)"

# Trava de seguranca repetida imediatamente antes da remocao.
if [[ "${BUCKET}" == "${BUCKET_COMPARTILHADO}" ]]; then
  erro "Recusando apagar '${BUCKET}': e' o bucket compartilhado."
fi

if ! gcloud storage buckets describe "gs://${BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  skip "Bucket gs://${BUCKET} nao existe (ja removido)."
else
  if [[ "${DELETE_BUCKET}" == "true" ]]; then
    printf '  Removendo bucket gs://%s e todo o seu conteudo...\n' "${BUCKET}"
    run gcloud storage rm --recursive "gs://${BUCKET}" --project="${PROJECT_ID}"
    ok "Bucket gs://${BUCKET} removido."
  else
    printf '  DELETE_BUCKET=false: removendo apenas os artefatos da aula...\n'
    run gcloud storage rm --recursive "gs://${BUCKET}/models/rf" --project="${PROJECT_ID}"
    ok "Objetos em gs://${BUCKET}/models/rf removidos; bucket mantido."
  fi
fi

# O bucket compartilhado e o dataset da gold NAO sao tocados. Intencional.
skip "gs://${BUCKET_COMPARTILHADO} preservado (infra de aulas anteriores)."
skip "Dataset ${PROJECT_ID}:${DATASET_COMPARTILHADO} preservado (camada gold da turma)."

# ---------------------------------------------------------------------------
# Conferencia final
# ---------------------------------------------------------------------------
info "Conferencia final (as tres listas abaixo devem sair vazias)"

printf '  Endpoints:\n'
gcloud ai endpoints list --region="${REGION}" --project="${PROJECT_ID}" \
  --filter="displayName=${ENDPOINT_DISPLAY_NAME}" --format="value(name)" 2>/dev/null \
  | sed 's/^/        /' || true

printf '  Modelos:\n'
gcloud ai models list --region="${REGION}" --project="${PROJECT_ID}" \
  --filter="displayName=${MODEL_DISPLAY_NAME}" --format="value(name)" 2>/dev/null \
  | sed 's/^/        /' || true

printf '  Bucket da aula:\n'
gcloud storage buckets describe "gs://${BUCKET}" --project="${PROJECT_ID}" \
  --format="value(name)" 2>/dev/null | sed 's/^/        /' || true

info "Teardown concluido"
cat <<EOF
  Ainda por sua conta, pelo console:
    - encerrar o runtime do notebook (BigQuery Studio / Colab Enterprise);
    - conferir Billing > Reports nas proximas 24h;
    - opcional: Billing > Budgets & alerts, criar um orcamento com
      alertas em 50%, 90% e 100% como rede de seguranca.
EOF
