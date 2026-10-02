# 03 — Salvar o artefato e registrar no Model Registry

Cobre as **seções 6 e 7** do notebook
[`notebooks/treino_experiments_registry.ipynb`](notebooks/treino_experiments_registry.ipynb): gravar o
`model.joblib` no Cloud Storage e registrar o modelo, com versionamento, no **Vertex AI Model Registry**.

| Item | Valor |
| --- | --- |
| Região | `us-central1` |
| Arquivo do artefato | `gs://SEU_PROJECT_ID-mlops-aula/models/rf/model.joblib` |
| Diretório do artefato (`artifact_uri`) | `gs://SEU_PROJECT_ID-mlops-aula/models/rf/` |
| Nome do modelo (`display_name`) | `rf-preco-imoveis` |
| Container de serving | `us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest` |
| Features (ordem canônica) | `[area_util, area_total, quartos, banheiros, garagens]` |

> **Registrar é gratuito.** O Model Registry não é tarifado pela entrada no catálogo. Paga-se só o
> armazenamento do artefato no GCS (centavos) e — depois, em
> [`04-deploy-endpoint.md`](04-deploy-endpoint.md) — o endpoint.

---

## 6. Salvar `model.joblib` no Cloud Storage

Duas regras que custam meia hora de depuração quando ignoradas:

1. o arquivo **precisa se chamar exatamente `model.joblib`** — é o nome que o container pré-construído
   do scikit-learn procura ao subir;
2. o `artifact_uri` do registro aponta para o **diretório** (`gs://.../models/rf/`), **nunca** para o
   arquivo.

```python
import joblib
from google.cloud import storage

joblib.dump(pipeline_final, "model.joblib")

storage.Client(project=PROJECT_ID) \
    .bucket(f"{PROJECT_ID}-mlops-aula") \
    .blob("models/rf/model.joblib") \
    .upload_from_filename("model.joblib")
```

Confira em **Cloud Storage > Buckets > `SEU_PROJECT_ID-mlops-aula` > `models/rf/`**.

**Compatibilidade de versão**: treine com `scikit-learn==1.6.*`, que é o container `sklearn-cpu.1-6`. Um
pickle de outra minor version falha ao carregar no serving — e o erro só aparece no deploy, 15 minutos
depois.

---

## 7. Registrar o modelo (e criar uma segunda versão)

### 7.1. Console — Vertex AI → Model Registry → Import

1. Menu de navegação → **Vertex AI** → *Deploy and use* → **Model Registry**. Confirme **us-central1**.
2. **Import**, no topo da lista.
3. **Name and region**:
   - *Import as new model* para a **v1**, com o nome **`rf-preco-imoveis`**;
   - *Import as new version of an existing model* para a **v2**, selecionando o `rf-preco-imoveis`
     existente (equivalente ao `parent_model` do SDK);
   - Região: **us-central1**.
4. **Model settings** → *Import model artifacts into a new pre-built container*:
   - **Model framework**: `scikit-learn`;
   - **Model framework version**: `1.6`;
   - **Accelerator type**: nenhum (CPU);
   - **Model artifact location**: `gs://SEU_PROJECT_ID-mlops-aula/models/rf/` — o **diretório**, com
     barra no final.
5. **Explainability** e demais seções: em branco (fora do escopo).
6. **Import**. Leva segundos — não confunda com o deploy (passo 04), que leva de 10 a 20 minutos.
7. Em **Version details**, a versão criada. Para promover: lista de versões → selecionar →
   **Set as default version**.

> O console preenche o `serving_container_image_uri` sozinho a partir do framework e da versão — é o
> mesmo `us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest`.

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

- Sem `parent_model`, o segundo upload cria **um segundo modelo solto no catálogo**, com o mesmo nome e
  nenhuma relação com o primeiro — o histórico se perde.
- **Aliases** dão nome de negócio às versões: o endpoint aponta para `campeao` ou `producao`, e promover
  um retreino vira mover o alias. O alias **`default` é reservado** e acompanha a versão com
  `is_default_version=True`.

> **`Model.list()` não mostra as versões.** Ele lista o **catálogo**: uma entrada por modelo, na versão
> *default*. Depois da v1 e da v2, ele imprime **uma única linha** (a v2). Para ver todas:

```python
# TODAS as versões de um modelo (v1, v2, ...)
for v in aiplatform.Model("1234567890").list_versions():
    print(v.version_id, v.version_aliases, v.version_description)
```

---

## Checkpoint

Antes de seguir para [`04-deploy-endpoint.md`](04-deploy-endpoint.md), confirme em
**Vertex AI → Model Registry**:

- existe **um** modelo `rf-preco-imoveis` (não dois);
- ele tem **duas versões**, com a versão 2 marcada como *default*;
- a *Model artifact location* aponta para o diretório `models/rf/`, e o arquivo lá dentro se chama
  `model.joblib`.

> No teardown, a ordem é sempre **undeploy → deletar endpoint → deletar modelo**: a deleção falha
> enquanto houver uma versão implantada.

---

Equivalentes em CLI e IaC: veja [`gcloud/README.md`](gcloud/README.md) e [`terraform/README.md`](terraform/README.md).
