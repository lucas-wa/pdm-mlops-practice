# 02 — Treino e rastreamento de experimentos

Acompanha as **seções 1 a 5** do notebook
[`notebooks/treino_experiments_registry.ipynb`](notebooks/treino_experiments_registry.ipynb). O notebook
é o que roda na aula; aqui ficam a explicação de cada passo e o caminho pelo console.

| Item | Valor |
| --- | --- |
| Região | `us-central1` |
| Projeto | `SEU_PROJECT_ID` |
| Tabela gold | `SEU_PROJECT_ID.aula_pdm.imoveis_gold` (ajuste para o nome da sua turma) |
| Bucket de artefatos | `gs://SEU_PROJECT_ID-mlops-aula` |
| Experimento | `preco-imoveis-rf` |
| Alvo | `preco` |
| Features (ordem canônica) | `[area_util, area_total, quartos, banheiros, garagens]` |

> **Experiments só existe em SDK e console.** Não há comando `gcloud` nem recurso Terraform para
> experimentos e runs. O único recurso Vertex AI correlato é `google_vertex_ai_tensorboard`, que **não
> usamos** — é pago por armazenamento.

> **Atenção ao TensorBoard automático.** Ao associar um experimento com
> `aiplatform.init(..., experiment=...)`, o SDK **cria sozinho** uma instância *Default Tensorboard*,
> tarifada por armazenamento. Nesta aula isso **não acontece porque passamos
> `experiment_tensorboard=False`** (seção 5). Por isso o [`gcloud/30_teardown.sh`](gcloud/30_teardown.sh)
> verifica a lista de TensorBoards no encerramento.

---

## 1. Ler a camada gold

O notebook lê a gold com o cliente do BigQuery e traz o resultado para um `DataFrame`:

```python
from google.cloud import bigquery

cliente_bq = bigquery.Client(project=PROJECT_ID)

sql = f"""
SELECT id, area_util, area_total, quartos, banheiros, garagens, bairro, cidade, preco
FROM `{GOLD_TABLE}`
WHERE preco IS NOT NULL AND preco > 0
"""

df = cliente_bq.query(sql).to_dataframe()
```

**Dependência escondida**: `to_dataframe()` precisa do pacote `db-dtypes` para converter colunas de
data/hora do BigQuery. Ele está no `%pip install` da seção 0 do notebook.

**Antes da aula**, confirme o nome exato da tabela e das colunas — o esquema da gold não é fixo. No
notebook muda só a variável `GOLD_TABLE` e, se necessário, a lista `COLUNAS_FEATURES`.

---

## 2. Deduplicar e dividir treino / validação / teste

Duas regras que decidem se o número reportado significa alguma coisa.

**Deduplicar por imóvel, antes de dividir.** As tabelas são append-only: o mesmo anúncio pode ter
entrado duas vezes. Se uma cópia cai no treino e outra na validação, o modelo é avaliado num imóvel que
já viu e o MAE fica artificialmente bom.

**Excluir colunas que vazam o alvo.** Qualquer coluna derivada do preço — `preco_fmt`, `preco_por_m2`,
faixa de preço — entrega a resposta ao modelo. A defesa é estrutural: `COLUNAS_FEATURES` é explícita e
nada entra sem passar por ela.

```python
df_unico = df.drop_duplicates(subset=["id"], keep="last").reset_index(drop=True)

X = df_unico[COLUNAS_FEATURES]     # só as 5 numéricas do contrato
y = df_unico["preco"].astype(float)

X_treino, X_resto, y_treino, y_resto = train_test_split(X, y, test_size=0.30, random_state=42)
X_val, X_teste, y_val, y_teste = train_test_split(X_resto, y_resto, test_size=0.50, random_state=42)
```

O `random_state=42` garante que a sala inteira chegue no mesmo split e compare os mesmos números.

---

## 3. Baseline: a mediana do preço de treino

Antes de treinar, a régua: chutar sempre a **mediana do preço de treino** e medir o **MAE** (erro
absoluto médio) na validação.

```python
mediana_treino = float(y_treino.median())
mae_baseline = float(mean_absolute_error(y_val, np.full(len(y_val), mediana_treino)))
```

O MAE se explica em uma frase: *em média, o modelo erra R$ X por anúncio*. E um modelo que não bate a
mediana não tem motivo para existir — o teste de sanidade que a maioria dos projetos pula.

---

## 4. O pipeline de treino

```python
def construir_pipeline(n_estimators=200, max_depth=12, random_state=42):
    return Pipeline(steps=[
        ("imputacao", SimpleImputer(strategy="median")),
        # n_jobs=2 e 200 arvores para caber em runtimes pequenos; -1 pode estourar memoria
        ("floresta", RandomForestRegressor(
            n_estimators=n_estimators, max_depth=max_depth,
            random_state=random_state, n_jobs=2)),
    ])
```

`n_jobs=-1` abre um processo por núcleo, cada um com sua cópia das árvores — num runtime modesto (o
padrão do BigQuery Studio) isso vira `MemoryError` no meio do treino. `n_jobs=2` paraleliza o
suficiente e mantém o consumo previsível.

O pipeline é deliberadamente pequeno, por razões de **serving**, não de modelagem:

- o container pré-construído entrega as `instances` ao `predict` como **array posicional** — sem nomes de
  coluna. Qualquer transformação que dependa de nome quebra;
- o `model.joblib` é desserializado num processo que **não importa este notebook**. `lambda` e
  `FunctionTransformer` com função local **não desserializam** lá;
- `SimpleImputer` e `RandomForestRegressor` são classes do próprio scikit-learn — o container as conhece.

Não há `StandardScaler` porque árvore não se importa com escala. O imputer entra porque a gold tem
buracos (nem todo anúncio informa vaga).

**`scikit-learn==1.6.*`** está pinado para casar com o container `sklearn-cpu.1-6`. Treinar numa versão e
servir em outra é a causa nº 1 de erro de unpickle no endpoint.

As categóricas `bairro` e `cidade` aparecem na célula opcional 5.2 do notebook, como exercício — mas o
modelo registrado e deployado é o numérico.

---

## 5. Rastrear os treinos no Vertex AI Experiments

Sem rastreamento, o resultado do treino morre quando o notebook fecha. O Experiments transforma cada
treino num **run** com parâmetros e métricas, guardado no projeto.

### SDK (o que roda na aula)

```python
from google.cloud import aiplatform

aiplatform.init(
    project=PROJECT_ID,
    location="us-central1",
    experiment="preco-imoveis-rf",
    staging_bucket="gs://SEU_PROJECT_ID-mlops-aula",
    # experiment_tensorboard=False evita criar uma instancia Default Tensorboard
    # (metricas-resumo nao precisam dela; ver 05-encerramento-custos)
    experiment_tensorboard=False,
)

aiplatform.start_run("run-a-20260928-140000")
aiplatform.log_params({
    "modelo": "RandomForestRegressor",
    "n_estimators": 200,
    "max_depth": 12,
    "features": "area_util,area_total,quartos,banheiros,garagens",
})
aiplatform.log_metrics({"mae": 128000.0, "mae_baseline": 210000.0})
aiplatform.end_run()
```

Depois de dois runs, a tabela comparativa sai em uma linha:

```python
aiplatform.get_experiment_df("preco-imoveis-rf")
```

O notebook roda **dois runs variando somente `max_depth`** — run A com `12`, run B com `24`, ambos com
`n_estimators=200`. Mudar um parâmetro por vez torna a comparação legível; manter 200 árvores nos dois
mantém o treino dentro da memória do runtime.

- **`log_metrics` são métricas-resumo e não exigem TensorBoard** — praticamente sem custo. Evitamos de
  propósito `log_time_series_metrics`, que exigiria uma instância **paga por armazenamento**;
- **não criamos TensorBoard porque passamos `experiment_tensorboard=False`.** Sem esse parâmetro, o SDK
  provisiona uma *Default Tensorboard* sozinho ao associar o experimento, mesmo com métricas-resumo;
- o nome do run precisa ser único dentro do experimento — o notebook carimba a hora
  (`run-a-%Y%m%d-%H%M%S`) para que reexecuções não colidam;
- `log_params` e `log_metrics` aceitam escalares. Listas viram texto — daí o
  `",".join(COLUNAS_FEATURES)`.

### Console (Vertex AI → Experiments)

1. Console do Google Cloud → menu de navegação → **Vertex AI**.
2. No menu lateral, seção *Model development*, clique em **Experiments**.
3. Confirme a região **us-central1** no seletor no topo da lista.
4. Clique no experimento **`preco-imoveis-rf`**. A lista de runs aparece com as colunas de parâmetros e
   métricas registradas.
5. **Comparar dois runs**: marque as caixas de `run-a-...` e `run-b-...` e clique em **Compare**. A tela
   mostra parâmetros e métricas lado a lado — o mesmo conteúdo do `get_experiment_df()`, num formato
   que quem não abriu o notebook consegue ler.
6. Clicando em um run individual, as abas *Parameters* e *Metrics* daquele run.

> Se a lista aparecer vazia logo depois de rodar as células, atualize a página: o registro é assíncrono.

---

## O que levar para o próximo passo

Ao final da seção 5 o notebook escolhe o run de menor MAE e avalia no **conjunto de teste** — a
estimativa honesta, em dados que nenhuma decisão de modelagem viu. É esse pipeline que segue para
[`03-model-registry.md`](03-model-registry.md).

---

Equivalentes em CLI e IaC: veja [`gcloud/README.md`](gcloud/README.md) e [`terraform/README.md`](terraform/README.md)
— mas note que **Experiments não tem equivalente**: é SDK ou console.
