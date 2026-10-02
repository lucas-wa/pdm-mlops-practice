# Caminho gcloud — a aula por linha de comando

Equivalente em `gcloud` do tutorial do console. A aula ao vivo usa o console; isto é **autoestudo**.

Os scripts são idempotentes. Rode-os a partir da raiz do material (`docs/aula-mlops-experiments-registry/`):

| Script | O que faz |
|---|---|
| [`seed_gold.sh`](seed_gold.sh) | Valida a camada gold e a reconstrói se estiver faltando ou mal formatada |
| [`00_setup.sh`](00_setup.sh) | APIs, IAM (opcional), bucket da aula e dataset |
| [`10_register_model.sh`](10_register_model.sh) | Registra `rf-preco-imoveis` no Model Registry |
| [`20_deploy_endpoint.sh`](20_deploy_endpoint.sh) | Cria o endpoint, implanta o modelo e prediz |
| [`30_teardown.sh`](30_teardown.sh) | **Encerra tudo na ordem correta** |

> **Consumo de créditos.** A turma usa **créditos educacionais** — não há cobrança no cartão de ninguém,
> mas os créditos são finitos. O **endpoint com modelo implantado é o maior consumidor**: tarifa por
> node-hora, 24/7, mesmo sem tráfego, e não desliga sozinho. Ao terminar, rode `30_teardown.sh` ou siga
> [`../05-encerramento-custos.md`](../05-encerramento-custos.md).

## Contrato de nomes

| Item | Valor |
|---|---|
| Região | `us-central1` |
| Bucket da aula | `SEU_PROJECT_ID-mlops-aula` |
| Bucket compartilhado (**não apagar**) | `SEU_PROJECT_ID-aula-pdm` |
| Dataset BigQuery | `aula_pdm` |
| Experiment | `preco-imoveis-rf` |
| Modelo | `rf-preco-imoveis` |
| Endpoint | `rf-preco-imoveis-endpoint` |
| `artifact_uri` (**diretório**) | `gs://SEU_PROJECT_ID-mlops-aula/models/rf/` |
| Arquivo do artefato | `model.joblib` — o nome exato que o container procura |
| Container de serving | `us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest` |
| Ordem canônica de features | `[area_util, area_total, quartos, banheiros, garagens]` |

---

## 0. Setup — APIs, IAM, bucket e dataset

Console equivalente: [`../01-setup-gcp.md`](../01-setup-gcp.md).

**Antes de tudo, garanta os dados.** O [`seed_gold.sh`](seed_gold.sh) valida a gold e só reconstrói se ela
estiver faltando ou sem as colunas do contrato:

```bash
# no Cloud Shell do seu projeto
bash gcloud/seed_gold.sh

# reconstruir mesmo que a gold já exista e esteja válida
bash gcloud/seed_gold.sh --force
```

Ele escreve apenas em `aula_pdm` (tabelas `anuncios` e `imoveis_gold`). Contrato de dados em
[`../00-pre-requisitos-e-gold.md`](../00-pre-requisitos-e-gold.md).

Tudo de uma vez:

```bash
# aluno Owner do próprio projeto: GRANT_IAM=false (roles/owner já cobre tudo)
PROJECT_ID=SEU_PROJECT_ID GRANT_IAM=false bash gcloud/00_setup.sh
```

Ou passo a passo:

```bash
gcloud auth login
gcloud config set project SEU_PROJECT_ID
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a

# Faturamento (pré-requisito; sem billing a API do Vertex AI não habilita)
gcloud billing projects describe SEU_PROJECT_ID
gcloud billing projects link SEU_PROJECT_ID --billing-account=SEU_BILLING_ACCOUNT_ID
```

**APIs** (`enable` é idempotente):

```bash
gcloud services enable \
  aiplatform.googleapis.com \
  storage.googleapis.com \
  bigquery.googleapis.com \
  compute.googleapis.com \
  dataform.googleapis.com \
  --project=SEU_PROJECT_ID

# só se a turma usar Vertex AI Workbench
gcloud services enable notebooks.googleapis.com --project=SEU_PROJECT_ID

gcloud services list --enabled --project=SEU_PROJECT_ID
```

**IAM — opcional.** Cada aluno é `Owner` do próprio projeto, e `roles/owner` já cobre tudo: **pule este
bloco**. Ele serve para projeto compartilhado ou service account dedicada:

```bash
PROJECT_ID="SEU_PROJECT_ID"
MEMBER="user:seu-email@dominio.com"
# ou: MEMBER="serviceAccount:aula-mlops@${PROJECT_ID}.iam.gserviceaccount.com"

for ROLE in \
  roles/aiplatform.user \
  roles/storage.objectAdmin \
  roles/bigquery.dataViewer \
  roles/bigquery.jobUser
do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="${MEMBER}" --role="${ROLE}" --condition=None
done

gcloud projects get-iam-policy "${PROJECT_ID}" \
  --flatten="bindings[].members" \
  --filter="bindings.members:${MEMBER}" \
  --format="table(bindings.role)"
```

**Bucket dedicado da aula** (`-mlops-aula`, novo; o `-aula-pdm` não é tocado):

```bash
PROJECT_ID="SEU_PROJECT_ID"
BUCKET="${PROJECT_ID}-mlops-aula"

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

gcloud storage buckets describe "gs://${BUCKET}" \
  --format="value(name, location, uniform_bucket_level_access)"
```

**Dataset `aula_pdm`** — normalmente já existe; confirme antes de criar:

```bash
PROJECT_ID="SEU_PROJECT_ID"
DATASET="aula_pdm"

bq --project_id="${PROJECT_ID}" show --format=prettyjson "${PROJECT_ID}:${DATASET}" \
  | grep -E '"location"|"datasetId"'

# só se estiver faltando
bq --project_id="${PROJECT_ID}" --location=us-central1 mk \
  --dataset \
  --description="Dados da disciplina PDM (camada gold)" \
  "${PROJECT_ID}:${DATASET}"

# descobrir o nome real da gold e conferir o schema
bq --project_id="${PROJECT_ID}" ls "${PROJECT_ID}:${DATASET}"
bq --project_id="${PROJECT_ID}" show --schema --format=prettyjson "${PROJECT_ID}:GOLD_TABLE"
```

**Verificação final** — tudo precisa responder sem erro:

```bash
PROJECT_ID="SEU_PROJECT_ID"
BUCKET="${PROJECT_ID}-mlops-aula"

gcloud services list --enabled --project="${PROJECT_ID}" \
  --filter="config.name:(aiplatform.googleapis.com OR storage.googleapis.com OR bigquery.googleapis.com OR compute.googleapis.com OR dataform.googleapis.com)" \
  --format="value(config.name)"

gcloud storage buckets describe "gs://${BUCKET}" --format="value(name, location)"
bq --project_id="${PROJECT_ID}" show --dataset "${PROJECT_ID}:aula_pdm"

# lista vazia é resultado válido
gcloud ai models list --region=us-central1 --project="${PROJECT_ID}"
```

O notebook roda no **BigQuery Studio** (importar o `.ipynb` + conectar o runtime, por console):
**Passo 6** de [`../01-setup-gcp.md`](../01-setup-gcp.md) — por isso `dataform.googleapis.com` na lista de APIs.

---

## 1–2. Treino e Experiments — não há gcloud

**Vertex AI Experiments não tem superfície em `gcloud ai ...`** (nem recurso Terraform). O experimento é
criado pelo SDK Python, na primeira chamada de `aiplatform.init(..., experiment="preco-imoveis-rf")`.

Use o notebook: [`../notebooks/treino_experiments_registry.ipynb`](../notebooks/treino_experiments_registry.ipynb)
— explicação em [`../02-treino-e-experiments.md`](../02-treino-e-experiments.md).

O `init` do notebook passa **`experiment_tensorboard=False`**: sem esse parâmetro o SDK cria sozinho uma
instância *Default Tensorboard*, tarifada por armazenamento.

---

## 3. Registrar o modelo

Console equivalente: [`../03-model-registry.md`](../03-model-registry.md). Script: `10_register_model.sh`.

```bash
PROJECT_ID=SEU_PROJECT_ID bash gcloud/10_register_model.sh
```

**Subir o artefato** (o arquivo precisa se chamar `model.joblib`):

```bash
gcloud storage cp model.joblib gs://SEU_PROJECT_ID-mlops-aula/models/rf/model.joblib
gcloud storage ls gs://SEU_PROJECT_ID-mlops-aula/models/rf/
```

**v1 — upload** (`--artifact-uri` é o **diretório**, com barra no final):

```bash
gcloud ai models upload \
  --region=us-central1 \
  --display-name=rf-preco-imoveis \
  --artifact-uri=gs://SEU_PROJECT_ID-mlops-aula/models/rf/ \
  --container-image-uri=us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest \
  --description="RandomForest para preço de anúncio a partir da gold de imóveis."
```

**Descobrir o MODEL_ID** (último segmento do resource name):

```bash
gcloud ai models list \
  --region=us-central1 \
  --filter='displayName=rf-preco-imoveis' \
  --format='value(name)'
```

**v2 — nova versão do mesmo modelo.** Sem `--parent-model`, o segundo upload cria um **segundo modelo
solto** no catálogo:

```bash
gcloud ai models upload \
  --region=us-central1 \
  --display-name=rf-preco-imoveis \
  --parent-model=1234567890 \
  --artifact-uri=gs://SEU_PROJECT_ID-mlops-aula/models/rf/ \
  --container-image-uri=us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest \
  --version-aliases=campeao \
  --version-description="Retreino com mais dados."
```

**Listar versões:**

```bash
gcloud ai models list-version 1234567890 --region=us-central1
```

> Para **promover** uma versão a padrão, use o SDK (`is_default_version=True`) ou o console
> (**Set as default version**). O caminho por gcloud varia entre releases — confirme com
> `gcloud ai models update --help`.

---

## 4. Deploy no endpoint e predição

Console equivalente: [`../04-deploy-endpoint.md`](../04-deploy-endpoint.md). Script: `20_deploy_endpoint.sh`.

```bash
PROJECT_ID=SEU_PROJECT_ID bash gcloud/20_deploy_endpoint.sh
```

> 💸 **A partir daqui começa o consumo por node-hora, 24/7, mesmo sem tráfego.**
> ⏱️ O deploy leva de **10 a 20 minutos**.

**Criar o endpoint:**

```bash
gcloud ai endpoints create \
  --region=us-central1 \
  --display-name=rf-preco-imoveis-endpoint
```

**Descobrir os IDs** (o ID numérico é o último segmento):

```bash
gcloud ai endpoints list \
  --region=us-central1 \
  --filter='displayName=rf-preco-imoveis-endpoint' \
  --format='value(name)'

gcloud ai models list \
  --region=us-central1 \
  --filter='displayName=rf-preco-imoveis' \
  --format='value(name)'
```

**Deployar o modelo:**

```bash
gcloud ai endpoints deploy-model ENDPOINT_ID \
  --region=us-central1 \
  --model=MODEL_ID \
  --display-name=rf-preco-imoveis \
  --machine-type=n1-standard-2 \
  --min-replica-count=1 \
  --max-replica-count=1 \
  --traffic-split=0=100
```

**Predizer.** O payload é **posicional**, na ordem canônica
`[area_util, area_total, quartos, banheiros, garagens]` — trocar a ordem não dá erro, dá resposta errada:

```bash
cat > request.json <<'JSON'
{
  "instances": [
    [120.0, 150.0, 3, 2, 1],
    [45.0, 55.0, 1, 1, 0]
  ]
}
JSON

gcloud ai endpoints predict ENDPOINT_ID \
  --region=us-central1 \
  --json-request=request.json
```

**Ver o que está deployado** (o `deployedModelId` é necessário para o undeploy):

```bash
gcloud ai endpoints describe ENDPOINT_ID \
  --region=us-central1 \
  --format='value(deployedModels[].id)'
```

---

## 5. Teardown — na ordem

Console equivalente: [`../05-encerramento-custos.md`](../05-encerramento-custos.md). Script: `30_teardown.sh`.

```bash
export PROJECT_ID="SEU_PROJECT_ID"
export REGION="us-central1"

bash gcloud/30_teardown.sh      # DRY_RUN=true para só listar
```

**A ordem não é arbitrária: não é possível deletar um modelo ainda implantado.**

**1. Endpoint (maior consumo):**

```bash
gcloud ai endpoints list --project="${PROJECT_ID}" --region="${REGION}" \
  --filter="displayName=rf-preco-imoveis-endpoint" --format="value(name)"
export ENDPOINT_ID="<id_retornado_acima>"

gcloud ai endpoints describe "${ENDPOINT_ID}" --project="${PROJECT_ID}" --region="${REGION}" \
  --format="value(deployedModels[].id)"
export DEPLOYED_MODEL_ID="<id_retornado_acima>"

gcloud ai endpoints undeploy-model "${ENDPOINT_ID}" \
  --project="${PROJECT_ID}" --region="${REGION}" --deployed-model-id="${DEPLOYED_MODEL_ID}"

gcloud ai endpoints delete "${ENDPOINT_ID}" --project="${PROJECT_ID}" --region="${REGION}" --quiet
```

**2. Runtime do notebook** (auto-shutdown ~180 min, mas apagar é o que encerra na hora):

```bash
gcloud colab runtimes list --project="${PROJECT_ID}" --region="${REGION}"
gcloud colab runtimes delete RUNTIME_ID --project="${PROJECT_ID}" --region="${REGION}" --quiet

# só se alguém usou Workbench (é uma VM)
gcloud workbench instances list --project="${PROJECT_ID}" --location="${REGION}-a"
gcloud workbench instances stop   INSTANCE_NAME --project="${PROJECT_ID}" --location="${REGION}-a"
gcloud workbench instances delete INSTANCE_NAME --project="${PROJECT_ID}" --location="${REGION}-a" --quiet
```

**3. TensorBoard — verificação.** A aula não cria nenhum (`experiment_tensorboard=False`), mas sem esse
parâmetro o SDK cria uma instância sozinho, tarifada por armazenamento (~US$ 10/GiB/mês):

```bash
gcloud ai tensorboards list --project="${PROJECT_ID}" --region="${REGION}"
gcloud ai tensorboards delete TENSORBOARD_ID --project="${PROJECT_ID}" --region="${REGION}" --quiet
```

**4. Modelo, versões e artefatos no GCS:**

```bash
gcloud ai models list --project="${PROJECT_ID}" --region="${REGION}" \
  --filter="displayName=rf-preco-imoveis"
export MODEL_ID="<id_retornado_acima>"

gcloud ai models list-version "${MODEL_ID}" --project="${PROJECT_ID}" --region="${REGION}"
gcloud ai models delete-version "${MODEL_ID}@2" --project="${PROJECT_ID}" --region="${REGION}" --quiet
gcloud ai models delete "${MODEL_ID}" --project="${PROJECT_ID}" --region="${REGION}" --quiet

gcloud storage ls -r "gs://${PROJECT_ID}-mlops-aula/"
gcloud storage rm -r "gs://${PROJECT_ID}-mlops-aula/models/"
```

> **NÃO APAGUE A INFRAESTRUTURA COMPARTILHADA:** o bucket `${PROJECT_ID}-aula-pdm` e o dataset
> `aula_pdm` (com a tabela gold) são das aulas anteriores e serão usados no Dia 2. Apagar é
> irreversível. Só o bucket com sufixo **`-mlops-aula`** contém artefatos desta aula.

**Varredura final** — as três primeiras devem sair vazias:

```bash
gcloud ai endpoints    list --project="${PROJECT_ID}" --region="${REGION}"
gcloud ai models       list --project="${PROJECT_ID}" --region="${REGION}"
gcloud ai tensorboards list --project="${PROJECT_ID}" --region="${REGION}"
gcloud storage ls "gs://${PROJECT_ID}-mlops-aula/"
```

**Budget de acompanhamento** (avisa, não bloqueia):

```bash
gcloud billing budgets create \
  --billing-account=SEU_BILLING_ACCOUNT_ID \
  --display-name="aula-mlops-vertex" \
  --budget-amount=50USD \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0 \
  --filter-projects="projects/SEU_PROJECT_ID"

gcloud billing budgets list --billing-account=SEU_BILLING_ACCOUNT_ID
```

---

Caminho declarativo: [`../terraform/README.md`](../terraform/README.md).
