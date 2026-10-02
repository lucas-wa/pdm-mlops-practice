# 03 — Salvar o artefato e registrar no Model Registry

Este documento cobre as **seções 6 e 7** do notebook
[`notebooks/treino_experiments_registry.ipynb`](notebooks/treino_experiments_registry.ipynb): gravar o
`model.joblib` no Cloud Storage e registrar o modelo — com versionamento — no **Vertex AI Model Registry**.

| Item | Valor |
| --- | --- |
| Região | `us-central1` |
| Arquivo do artefato | `gs://SEU_PROJECT_ID-mlops-aula/models/rf/model.joblib` |
| Diretório do artefato (`artifact_uri`) | `gs://SEU_PROJECT_ID-mlops-aula/models/rf/` |
| Nome do modelo (`display_name`) | `rf-preco-imoveis` |
| Container de serving | `us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest` |
| Features (ordem canônica) | `[area_util, area_total, quartos, banheiros, garagens]` |

> **Registrar é gratuito.** O Model Registry não é tarifado pela entrada no catálogo. Você paga apenas o
> armazenamento do artefato no GCS (alguns KB, centavos) e — só depois, em
> [`04-deploy-endpoint.md`](04-deploy-endpoint.md) — o endpoint.

> **Terraform não registra modelos treinados.** Não existe recurso `google_vertex_ai_model` no provider
> `hashicorp/google`. O Terraform cuida de APIs, bucket e dataset (veja `01-setup-gcp.md`); o registro do
> modelo é sempre console, SDK ou gcloud. Por isso os três blocos abaixo são **Console | SDK | gcloud**.

---

## 6. Salvar `model.joblib` no Cloud Storage

Duas regras que costumam custar meia hora de depuração:

1. o arquivo **precisa se chamar exatamente `model.joblib`**. Não `modelo.joblib`, não `model.pkl`. É o
   nome que o container pré-construído do scikit-learn procura ao subir;
2. o `artifact_uri` do registro aponta para o **diretório** que contém o arquivo
   (`gs://.../models/rf/`), **nunca** para o arquivo em si.

```python
import joblib
from google.cloud import storage

joblib.dump(pipeline_final, "model.joblib")

storage.Client(project=PROJECT_ID) \
    .bucket(f"{PROJECT_ID}-mlops-aula") \
    .blob("models/rf/model.joblib") \
    .upload_from_filename("model.joblib")
```

Equivalente em linha de comando:

```bash
gcloud storage cp model.joblib gs://SEU_PROJECT_ID-mlops-aula/models/rf/model.joblib
gcloud storage ls gs://SEU_PROJECT_ID-mlops-aula/models/rf/
```

**Compatibilidade de versão**: o pipeline foi treinado com `scikit-learn==1.6.*` justamente porque o
container é o `sklearn-cpu.1-6`. Um pickle gerado por outra minor version pode falhar ao carregar no
serving — e o erro só aparece no deploy, 15 minutos depois.

---

## 7. Registrar o modelo (e criar uma segunda versão)

### 7.1. Console — Vertex AI → Model Registry → Import

1. Console do Google Cloud → menu de navegação → **Vertex AI**.
2. Menu lateral, seção *Deploy and use* → **Model Registry**. Confirme a região **us-central1**.
3. Clique em **Import** (ou **Importar**), no topo da lista.
4. **Name and region**:
   - *Import as new model*: marque esta opção para a **v1** e digite o nome **`rf-preco-imoveis`**;
   - *Import as new version of an existing model*: use esta opção para a **v2**, selecionando o modelo
     `rf-preco-imoveis` já existente. É isso que o `parent_model` faz no SDK.
   - Região: **us-central1**.
5. **Model settings** → *Import model artifacts into a new pre-built container*:
   - **Model framework**: `scikit-learn`;
   - **Model framework version**: `1.6`;
   - **Accelerator type**: nenhum (CPU);
   - **Model artifact location**: `gs://SEU_PROJECT_ID-mlops-aula/models/rf/`
     — o **diretório**, com a barra no final, não o arquivo.
6. **Explainability** e as demais seções: deixe em branco (fora do escopo desta aula).
7. Clique em **Import**. O registro leva alguns segundos — não confunda com o deploy, que é o passo 04 e
   leva de 10 a 20 minutos.
8. Na tela do modelo, a aba **Version details** mostra a versão criada. Para promover uma versão a padrão,
   abra a lista de versões, selecione a desejada e use **Set as default version**.

> O console preenche o `serving_container_image_uri` sozinho a partir do framework e da versão que você
> escolheu no passo 5. É o mesmo `us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest` que o SDK
> passa explicitamente.

### 7.2. SDK Python (o que roda no notebook)

**v1 — criar a entrada no catálogo:**

```python
from google.cloud import aiplatform

aiplatform.init(project=PROJECT_ID, location="us-central1")

modelo_v1 = aiplatform.Model.upload(
    display_name="rf-preco-imoveis",
    artifact_uri="gs://SEU_PROJECT_ID-mlops-aula/models/rf/",
    serving_container_image_uri="us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest",
    description="RandomForest para preço de anúncio a partir da gold de imóveis.",
    labels={"aula": "mlops", "framework": "sklearn"},
    sync=True,
)

print(modelo_v1.resource_name)   # projects/.../locations/us-central1/models/1234567890
print(modelo_v1.version_id)      # 1
```

**v2 — nova versão do mesmo modelo:**

```python
modelo_v2 = aiplatform.Model.upload(
    display_name="rf-preco-imoveis",
    parent_model=modelo_v1.resource_name,      # <- é isto que cria VERSÃO, não modelo novo
    artifact_uri="gs://SEU_PROJECT_ID-mlops-aula/models/rf/",
    serving_container_image_uri="us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest",
    version_description="Retreino com mais dados — MAE validação R$ ...",
    is_default_version=True,
    version_aliases=["campeao"],
    sync=True,
)

print(modelo_v2.version_id)         # 2
print(modelo_v2.version_aliases)    # ['campeao', 'default']
```

Sem `parent_model`, o segundo `upload` criaria **um segundo modelo solto no catálogo**, com o mesmo nome
e nenhuma relação com o primeiro — e o histórico se perderia.

**Aliases** dão nome de negócio às versões. Em vez de o endpoint apontar para "versão 2", ele aponta para
`campeao` ou `producao`, e promover um retreino vira mover o alias. O alias **`default` é reservado** e
acompanha a versão marcada com `is_default_version=True`.

**Listar o catálogo:**

```python
# UMA linha por modelo, sempre na versão DEFAULT — este é o catálogo, não o histórico.
for m in aiplatform.Model.list(filter='display_name="rf-preco-imoveis"'):
    print(m.version_id, m.resource_name, m.version_aliases)
```

> **`Model.list()` não mostra as versões.** Ele lista o **catálogo**: uma entrada por modelo, na versão
> marcada como *default*. Depois de registrar a v1 e a v2, este loop imprime **uma única linha** (a v2) —
> e não o histórico. Para ver **todas** as versões:

```python
# TODAS as versões de um modelo (v1, v2, ...)
for v in aiplatform.Model("1234567890").list_versions():
    print(v.version_id, v.version_aliases, v.version_description)
```

```bash
gcloud ai models list-version 1234567890 --region=us-central1
```

### 7.3. gcloud

O script [`scripts/10_register_model.sh`](scripts/10_register_model.sh) executa exatamente estes comandos
de forma idempotente.

**v1 — upload:**

```bash
gcloud ai models upload \
  --region=us-central1 \
  --display-name=rf-preco-imoveis \
  --artifact-uri=gs://SEU_PROJECT_ID-mlops-aula/models/rf/ \
  --container-image-uri=us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest \
  --description="RandomForest para preço de anúncio a partir da gold de imóveis."
```

**Descobrir o MODEL_ID:**

```bash
gcloud ai models list \
  --region=us-central1 \
  --filter='displayName=rf-preco-imoveis' \
  --format='value(name)'
# devolve projects/.../locations/us-central1/models/1234567890 — o ID é o último segmento
```

**v2 — nova versão do mesmo modelo:**

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

**Apagar (no encerramento — veja `05-encerramento-custos.md`):**

```bash
# uma versão específica
gcloud ai models delete-version 1234567890@2 --region=us-central1

# o modelo inteiro, com todas as versões
gcloud ai models delete 1234567890 --region=us-central1
```

> O `delete` **falha enquanto houver uma versão deployada** em algum endpoint. A ordem correta do
> teardown é sempre: undeploy → deletar endpoint → deletar modelo.

> Para **promover** uma versão existente a padrão, use o SDK (`is_default_version=True` no upload) ou o
> console (**Set as default version**). O caminho por gcloud para trocar a versão padrão de um modelo já
> registrado varia entre releases do SDK — confirme com `gcloud ai models update --help` antes de
> depender dele num script.

---

## Checkpoint

Antes de seguir para [`04-deploy-endpoint.md`](04-deploy-endpoint.md), confirme no console
(**Vertex AI → Model Registry**) que:

- existe **um** modelo `rf-preco-imoveis` (não dois);
- ele tem **duas versões**, e a versão 2 está marcada como *default*;
- a *Model artifact location* aponta para o diretório `models/rf/`, e o arquivo lá dentro se chama
  `model.joblib`.
