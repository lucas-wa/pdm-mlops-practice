# 02 — Treino e rastreamento de experimentos

Acompanha as **seções 1 a 5** do notebook
[`notebooks/treino_experiments_registry.ipynb`](notebooks/treino_experiments_registry.ipynb) — o notebook
é o que roda na aula; aqui ficam a explicação e o caminho pelo console.

**Onde rodar:** importe e execute o notebook no **BigQuery Studio** — ver Passo 6 de
[`01-setup-gcp.md`](01-setup-gcp.md).

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

---

## 1. Ler a camada gold

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

- **Dependência escondida**: `to_dataframe()` precisa do pacote `db-dtypes` (já no `%pip install` da
  seção 0 do notebook).
- **Antes da aula**, confirme o nome exato da tabela e das colunas. No notebook muda só a variável
  `GOLD_TABLE` e, se necessário, a lista `COLUNAS_FEATURES`.

---

## 2. Deduplicar e dividir treino / validação / teste

Duas regras que decidem se o número reportado significa alguma coisa.

- **Deduplicar por imóvel, antes de dividir.** As tabelas são append-only: se uma cópia cai no treino e
  outra na validação, o MAE fica artificialmente bom.
- **Excluir colunas que vazam o alvo** (`preco_fmt`, `preco_por_m2`, faixa de preço). A defesa é
  estrutural: `COLUNAS_FEATURES` é explícita e nada entra sem passar por ela.

```python
df_unico = df.drop_duplicates(subset=["id"], keep="last").reset_index(drop=True)

X = df_unico[COLUNAS_FEATURES]     # só as 5 numéricas do contrato
y = df_unico["preco"].astype(float)

X_treino, X_resto, y_treino, y_resto = train_test_split(X, y, test_size=0.30, random_state=42)
X_val, X_teste, y_val, y_teste = train_test_split(X_resto, y_resto, test_size=0.50, random_state=42)
```

O `random_state=42` só reproduz o mesmo split se a **ordem das linhas for a mesma** para todos — por isso a consulta da seção 1 termina com `ORDER BY id`. Sem essa ordenação, o BigQuery devolve as linhas em ordem arbitrária, cada aluno cai num split diferente e o **MAE do baseline sai diferente**, mesmo com os mesmos dados.

---

## 3. Baseline: a mediana do preço de treino

A régua antes do modelo: chutar sempre a **mediana do preço de treino** e medir o **MAE** na validação.

```python
mediana_treino = float(y_treino.median())
mae_baseline = float(mean_absolute_error(y_val, np.full(len(y_val), mediana_treino)))
```

O MAE se lê como *em média, o modelo erra R$ X por anúncio*. Um modelo que não bate a mediana não tem
motivo para existir.

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

O pipeline é pequeno por razões de **serving**, não de modelagem:

- `n_jobs=-1` abre um processo por núcleo, cada um com sua cópia das árvores — no runtime padrão do
  BigQuery Studio isso vira `MemoryError`. `n_jobs=2` mantém o consumo previsível;
- o container pré-construído entrega as `instances` ao `predict` como **array posicional**, sem nomes de
  coluna: qualquer transformação que dependa de nome quebra;
- o `model.joblib` é desserializado num processo que **não importa este notebook** — `lambda` e
  `FunctionTransformer` com função local não desserializam lá;
- `SimpleImputer` e `RandomForestRegressor` são classes do próprio scikit-learn, que o container conhece;
- sem `StandardScaler`: árvore não se importa com escala. O imputer entra porque a gold tem buracos.

**`scikit-learn==1.6.*`** está pinado para casar com o container `sklearn-cpu.1-6`. Treinar numa versão e
servir em outra é a causa nº 1 de erro de unpickle no endpoint.

As categóricas `bairro` e `cidade` ficam na célula opcional 5.2 do notebook — o modelo registrado e
deployado é o numérico.

---

## 5. Rastrear os treinos no Vertex AI Experiments

Sem rastreamento, o resultado morre quando o notebook fecha. Cada treino vira um **run** com parâmetros e
métricas, guardado no projeto.

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
`n_estimators=200`.

- **`experiment_tensorboard=False` é obrigatório aqui**: sem ele o SDK provisiona sozinho uma instância
  *Default Tensorboard*, tarifada por armazenamento, ao associar o experimento. Por isso o
  [`gcloud/30_teardown.sh`](gcloud/30_teardown.sh) confere a lista de TensorBoards no encerramento;
- `log_metrics` grava métricas-resumo, que não exigem TensorBoard — praticamente sem custo. Evitamos
  `log_time_series_metrics`, que exigiria a instância paga;
- o nome do run precisa ser único no experimento — o notebook carimba a hora (`run-a-%Y%m%d-%H%M%S`);
- `log_params` e `log_metrics` aceitam escalares; listas viram texto, daí o `",".join(COLUNAS_FEATURES)`.

### Console (Vertex AI → Experiments)

1. Menu de navegação → **Vertex AI** → seção *Model development* → **Experiments**.
2. Confirme a região **us-central1** no seletor do topo.
3. Clique no experimento **`preco-imoveis-rf`**: a lista de runs aparece com parâmetros e métricas.
4. **Comparar dois runs**: marque `run-a-...` e `run-b-...` → **Compare**. É o mesmo conteúdo do
   `get_experiment_df()`, legível para quem não abriu o notebook.
5. Clicando em um run individual, as abas *Parameters* e *Metrics* daquele run.

> Lista vazia logo após rodar as células: atualize a página, o registro é assíncrono.

---

## O que levar para o próximo passo

Ao final da seção 5 o notebook escolhe o run de menor MAE e avalia no **conjunto de teste** — a
estimativa honesta, em dados que nenhuma decisão de modelagem viu. É esse pipeline que segue para
[`03-model-registry.md`](03-model-registry.md).

---

Equivalentes em CLI e IaC: veja [`gcloud/README.md`](gcloud/README.md) e [`terraform/README.md`](terraform/README.md)
— mas note que **Experiments não tem equivalente**: é SDK ou console.
