# 04 — Deploy em Endpoint e predição online

Cobre as **seções 8 e 9** do notebook
[`notebooks/treino_experiments_registry.ipynb`](notebooks/treino_experiments_registry.ipynb): subir o
modelo registrado num **Endpoint** do Vertex AI e fazer a primeira predição online.

| Item | Valor |
| --- | --- |
| Região | `us-central1` |
| Endpoint (`display_name`) | `rf-preco-imoveis-endpoint` |
| Modelo | `rf-preco-imoveis` (versão padrão / alias `campeao`) |
| Máquina | `n1-standard-2`, 1 réplica |
| Container | `us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.1-6:latest` |

> ## 💸 Este é o passo que mais consome créditos
>
> A turma usa **créditos educacionais** — não há cobrança em cartão. Mas um modelo implantado consome
> **por node-hora, 24 horas por dia, mesmo sem nenhuma requisição**. Com `min-replica-count=1` há uma
> `n1-standard-2` ligada até alguém desligá-la, e o endpoint **não** tem auto-desligamento.
>
> Rode o checklist de [`05-encerramento-custos.md`](05-encerramento-custos.md) antes de encerrar a aula.
> Undeploy e deleção do endpoint são o primeiro item da lista.

> ## ⏱️ O deploy leva de 10 a 20 minutos
>
> **Dispare o deploy cedo**, assim que o modelo estiver registrado, e use o tempo de provisionamento
> para discutir Experiments e Registry.
>
> **Contingência**: o docente mantém um **endpoint de referência já provisionado** para demonstrar a
> predição caso o deploy do grupo não conclua a tempo — serve só para a demonstração, não conta como
> entrega.
>
> **Erro transitório**: às vezes o deploy termina com `ERROR: ... System error. Please try this
> operation again.` (falha de infraestrutura do Google, não do seu modelo). O endpoint continua criado
> e **vazio não consome créditos**: basta **repetir o deploy**. Só investigue logs do container se
> falhar de forma consistente.

---

## O contrato de entrada — leia antes de testar

O container pré-construído entrega as `instances` ao `predict` como **array posicional**: não há nomes
de coluna no payload. A única coisa que liga um número à feature certa é a **posição**.

> ### ORDEM CANÔNICA DO VETOR DE FEATURES
>
> ```
> [area_util, area_total, quartos, banheiros, garagens]
> ```
>
> | Posição | Feature | Tipo | Exemplo |
> | --- | --- | --- | --- |
> | 0 | `area_util` | float (m²) | `120.0` |
> | 1 | `area_total` | float (m²) | `150.0` |
> | 2 | `quartos` | int | `3` |
> | 3 | `banheiros` | int | `2` |
> | 4 | `garagens` | int | `1` |

Trocar `quartos` por `banheiros` no payload **não gera erro** — gera uma predição errada em silêncio.

Payload de exemplo (duas instâncias):

```json
{
  "instances": [
    [120.0, 150.0, 3, 2, 1],
    [45.0, 55.0, 1, 1, 0]
  ]
}
```

---

## 8. Criar o endpoint e fazer o deploy

### 8.1. Console — a partir do Model Registry

1. Console → menu de navegação → **Vertex AI**.
2. Menu lateral, *Deploy and use* → **Model Registry**. Região **us-central1**.
3. Clique em **`rf-preco-imoveis`** → escolha a versão *default* → **Deploy & test** →
   **Deploy to endpoint**.
4. **Define your endpoint**:
   - *Create new endpoint*;
   - **Endpoint name**: `rf-preco-imoveis-endpoint`;
   - **Access**: *Standard* (endpoint público);
   - Região: **us-central1**.
5. **Model settings**:
   - **Traffic split**: `100`;
   - **Machine type**: `n1-standard-2`;
   - **Minimum / Maximum number of compute nodes**: `1` e `1`;
   - **Accelerator**: nenhum; *Logging*: padrões.
6. **Model monitoring** e **Explainability**: pule.
7. **Deploy**. ⏱️ **Agora espere de 10 a 20 minutos.** O status aparece em **Vertex AI → Online
   prediction → Endpoints**; enquanto estiver *Deploying*, o endpoint ainda não responde.

**Caminho alternativo:** **Vertex AI → Online prediction → Endpoints → Create** → nome
`rf-preco-imoveis-endpoint`, região `us-central1` → depois **Add model**.

**Testar pelo console:**

1. **Vertex AI → Online prediction → Endpoints** → `rf-preco-imoveis-endpoint`.
2. Aba **Test your model**.
3. No campo **JSON request**, cole o payload:

   ```json
   {"instances": [[120.0, 150.0, 3, 2, 1]]}
   ```

4. **Predict**. A resposta traz `predictions` com o preço estimado.

### 8.2. SDK Python (o que roda no notebook)

```python
from google.cloud import aiplatform

aiplatform.init(project=PROJECT_ID, location="us-central1")

# idempotente: reaproveita o endpoint se já existir (não duplique custo em reexecuções)
endpoints = aiplatform.Endpoint.list(filter='display_name="rf-preco-imoveis-endpoint"')
endpoint = endpoints[0] if endpoints else aiplatform.Endpoint.create(
    display_name="rf-preco-imoveis-endpoint"
)

# 10 a 20 minutos
modelo_v2.deploy(
    endpoint=endpoint,
    deployed_model_display_name="rf-preco-imoveis",
    machine_type="n1-standard-2",
    min_replica_count=1,
    max_replica_count=1,
    traffic_percentage=100,
    sync=True,
)
```

Predição — a instância segue a **ordem canônica**:

```python
# [area_util, area_total, quartos, banheiros, garagens]
resposta = endpoint.predict(instances=[[120.0, 150.0, 3, 2, 1]])

print(resposta.predictions)             # [845123.4]
print(resposta.model_version_id)        # qual VERSÃO respondeu
print(resposta.deployed_model_id)
```

---

## 9. O teste de fechamento

O que fecha a aula não é a predição em si — é conseguir dizer **qual versão do modelo respondeu**:

```python
resposta = endpoint.predict(instances=[[120.0, 150.0, 3, 2, 1]])

print("predição:", resposta.predictions[0])
print("modelo  :", resposta.model_resource_name)
print("versão  :", resposta.model_version_id)
```

Sem isso, quando o número mudar amanhã, ninguém sabe dizer se mudou o modelo ou mudou o mundo. Essa
rastreabilidade — experimento → versão registrada → versão servida — é o que a aula inteira construiu.

---

## ⚠️ Antes de fechar o notebook

O endpoint continua consumindo créditos. Vá agora para
**[`05-encerramento-custos.md`](05-encerramento-custos.md)** e rode o checklist nesta ordem:

1. undeploy do modelo no endpoint;
2. deletar o endpoint;
3. deletar o modelo / as versões no Registry;
4. remover os artefatos do GCS;
5. parar o runtime do notebook.

A ordem importa: **não é possível deletar um modelo que ainda está implantado**.

---

Equivalentes em CLI e IaC: veja [`gcloud/README.md`](gcloud/README.md) e [`terraform/README.md`](terraform/README.md).
