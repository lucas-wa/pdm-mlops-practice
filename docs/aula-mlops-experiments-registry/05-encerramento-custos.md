# 05 — Encerramento e custos

Este é o documento mais importante da aula. Ele encerra os recursos criados, na ordem correta, e configura as proteções que evitam surpresas na fatura.

> **Execute este checklist ao final da aula, com a turma, item a item.**
>
> O recurso mais caro desta aula — o **Endpoint com modelo implantado** — cobra **por node-hora, 24 horas por dia, mesmo sem nenhuma requisição**. Ele não desliga sozinho. Se ficar esquecido, continua cobrando indefinidamente.

Tudo o que está aqui também está automatizado, na mesma ordem e de forma idempotente, em [`scripts/30_teardown.sh`](scripts/30_teardown.sh).

---

## 1. Ordem de custo (do mais caro ao mais barato)

Encerre **nesta ordem**. Ela não é arbitrária: além de resolver primeiro o que mais custa, respeita as dependências entre os recursos.

| # | Recurso | Por que custa | Urgência |
|---|---|---|---|
| 1 | **Endpoint com modelo implantado** | Nós cobrados **por hora, 24/7**, mesmo ociosos. Não desliga sozinho | **Crítica** |
| 2 | **Runtime do notebook** (BigQuery Studio / Colab Enterprise; ou VM do Workbench) | Cobra enquanto está ativo | Alta |
| 3 | **Instância de TensorBoard** | Cobrança por armazenamento, na ordem de **US$ 10/GiB/mês**. Nesta aula **não criamos nenhuma porque passamos `experiment_tensorboard=False`** no `aiplatform.init(...)` — sem esse parâmetro o SDK criaria uma sozinha | Média (se existir) |
| 4 | **Modelo, versões e objetos no GCS** | Custo baixo, de armazenamento | Baixa |

> **Dependência que quebra o teardown:** não é possível deletar um modelo que ainda está **implantado** em um endpoint. É preciso fazer o **undeploy** primeiro. Por isso o passo 1 vem antes do passo 4 — e por isso tentar apagar o modelo primeiro gera um erro que costuma travar a turma.

> **Registrar modelo no Model Registry é GRATUITO.** Não há cobrança pelo registro nem pelo versionamento. O que se paga é o armazenamento do artefato no GCS (centavos) e, principalmente, o **endpoint** onde a versão é implantada.

---

## 2. Passo 1 — Undeploy e deleção do endpoint (o mais caro)

### 2.1 Undeploy do modelo

**Console:**

1. Console do Google Cloud → **Vertex AI** → **Online prediction** → **Endpoints**.
2. Confirmar a região **`us-central1`** no seletor.
3. Clicar em **`rf-preco-imoveis-endpoint`**.
4. Na lista de modelos implantados, no menu de três pontos da linha do modelo, escolher **Undeploy model** (*Remover implantação do modelo*).
5. Confirmar e **aguardar a conclusão**. Enquanto o undeploy não terminar, os nós continuam cobrando.

**gcloud:**

```bash
export PROJECT_ID="SEU_PROJECT_ID"
export REGION="us-central1"

# 1. Localizar o endpoint
gcloud ai endpoints list \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --filter="displayName=rf-preco-imoveis-endpoint" \
  --format="value(name)"

export ENDPOINT_ID="<id_retornado_acima>"

# 2. Descobrir o deployed model id
gcloud ai endpoints describe "${ENDPOINT_ID}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --format="value(deployedModels[].id)"

export DEPLOYED_MODEL_ID="<id_retornado_acima>"

# 3. Undeploy
gcloud ai endpoints undeploy-model "${ENDPOINT_ID}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --deployed-model-id="${DEPLOYED_MODEL_ID}"
```

### 2.2 Deleção do endpoint

**Console:**

1. Ainda em **Vertex AI** → **Online prediction** → **Endpoints**.
2. Marcar **`rf-preco-imoveis-endpoint`** (agora sem modelos implantados).
3. **Delete** (*Excluir*) e confirmar.

**gcloud:**

```bash
gcloud ai endpoints delete "${ENDPOINT_ID}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --quiet
```

- [ ] Undeploy concluído
- [ ] Endpoint deletado
- [ ] Lista de Endpoints em `us-central1` está **vazia**

---

## 3. Passo 2 — Runtime do notebook

### 3.1 BigQuery Studio / Colab Enterprise (ambiente desta aula)

Há desligamento automático por inatividade (aproximadamente **180 minutos**), mas **apagar o runtime é o que garante** o encerramento imediato.

**Console:**

1. Console → **Vertex AI** → **Colab Enterprise** → **Runtimes** (*Ambientes de execução*).
2. Confirmar a região **`us-central1`**.
3. Selecionar o runtime usado na aula.
4. **Delete** (*Excluir*). Apenas desconectar o notebook **não** encerra o runtime.

Alternativa pelo BigQuery: **BigQuery** → **BigQuery Studio** → menu do notebook → desconectar e, em seguida, apagar o runtime pela tela do Colab Enterprise acima.

**gcloud:**

```bash
gcloud colab runtimes list \
  --project="${PROJECT_ID}" \
  --region="${REGION}"

gcloud colab runtimes delete RUNTIME_ID \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --quiet
```

> Se o comando `gcloud colab` não estiver disponível na sua versão do SDK, use o console. O caminho pelo console é o oficial da aula.

### 3.2 Vertex AI Workbench (só se alguém usou)

Workbench é uma **VM**: ela cobra enquanto estiver ligada, mesmo sem notebook aberto.

**Console:**

1. Console → **Vertex AI** → **Workbench** → **Instances**.
2. **Stop** (*Parar*) a instância — interrompe a cobrança de computação.
3. **Delete** (*Excluir*) a instância — encerra também o disco.

**gcloud:**

```bash
gcloud workbench instances list \
  --project="${PROJECT_ID}" \
  --location="${REGION}-a"

gcloud workbench instances stop INSTANCE_NAME \
  --project="${PROJECT_ID}" \
  --location="${REGION}-a"

gcloud workbench instances delete INSTANCE_NAME \
  --project="${PROJECT_ID}" \
  --location="${REGION}-a" \
  --quiet
```

- [ ] Runtime do BigQuery Studio / Colab Enterprise deletado
- [ ] Instância do Workbench parada e deletada (se houver)

---

## 4. Passo 3 — TensorBoard (verificação)

> **Nesta aula NÃO criamos nenhuma instância de TensorBoard — porque passamos `experiment_tensorboard=False` no `aiplatform.init(...)`.** As métricas-resumo do Vertex AI Experiments (`mae`, `mae_baseline`) **não exigem TensorBoard**, e com esse parâmetro o rastreamento sai praticamente sem custo.

**Sem esse parâmetro, o SDK cria uma instância *Default Tensorboard* automaticamente** ao associar o experimento no `init` — não é preciso pedir nada, nem usar `log_time_series_metrics`. Por isso este passo é uma **verificação**, e não uma formalidade: se alguém rodou o `init` sem `experiment_tensorboard=False` (ou seguiu outro tutorial), a instância está lá. A cobrança é por **armazenamento**, na ordem de **US$ 10 por GiB por mês** — **confirme o valor atual no pricing do Vertex AI ao vivo**, porque preços mudam.

**Console:**

1. Console → **Vertex AI** → **Experiments** → aba **TensorBoard instances**.
2. Confirmar a região **`us-central1`**.
3. Se houver alguma instância, selecionar e **Delete**.

**gcloud:**

```bash
gcloud ai tensorboards list \
  --project="${PROJECT_ID}" \
  --region="${REGION}"

# Apenas se a lista acima retornar algo
gcloud ai tensorboards delete TENSORBOARD_ID \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --quiet
```

- [ ] Lista de TensorBoard instances verificada e **vazia**

---

## 5. Passo 4 — Modelo, versões e objetos no GCS

Custo baixo, mas o passo mantém o projeto limpo e fecha o ciclo da aula.

### 5.1 Versões e modelo no Model Registry

**Console:**

1. Console → **Vertex AI** → **Model Registry**.
2. Confirmar a região **`us-central1`**.
3. Clicar em **`rf-preco-imoveis`** → aba de **versões**.
4. Deletar as **versões** (menu de três pontos → *Delete version*) e depois o **modelo**.

**gcloud:**

```bash
# Listar modelos
gcloud ai models list \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --filter="displayName=rf-preco-imoveis"

export MODEL_ID="<id_retornado_acima>"

# Listar versões
gcloud ai models list-version "${MODEL_ID}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}"

# Deletar uma versão específica
gcloud ai models delete-version "${MODEL_ID}@2" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --quiet

# Deletar o modelo (todas as versões)
gcloud ai models delete "${MODEL_ID}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --quiet
```

> Se a deleção falhar com erro de modelo em uso, **o undeploy do passo 1 não foi concluído**. Volte à seção 2.

### 5.2 Objetos no bucket da aula

**Console:**

1. Console → **Cloud Storage** → **Buckets** → **`${PROJECT_ID}-mlops-aula`**.
2. Entrar na pasta `models/` e excluir os objetos da aula.

**gcloud / gcloud storage:**

```bash
# Conferir o que existe antes de apagar
gcloud storage ls -r "gs://${PROJECT_ID}-mlops-aula/"

# Remover os artefatos do modelo
gcloud storage rm -r "gs://${PROJECT_ID}-mlops-aula/models/"
```

O SDK do Vertex AI usa o mesmo bucket como **staging** (`staging_bucket` no `aiplatform.init`) e pode ter criado pastas auxiliares. Como `${PROJECT_ID}-mlops-aula` é dedicado a esta aula, é seguro esvaziá-lo por inteiro:

```bash
gcloud storage rm -r "gs://${PROJECT_ID}-mlops-aula/**"
```

> **NÃO APAGUE A INFRAESTRUTURA COMPARTILHADA**
>
> - O bucket **`${PROJECT_ID}-aula-pdm`** é das aulas anteriores e será usado no Dia 2. **Não apague, não esvazie.**
> - O dataset **`aula_pdm`** e a **tabela gold** também permanecem. **Não apague.**
> - Apagar por engano é **irreversível** e derruba o material das próximas aulas.
>
> Só o bucket **`${PROJECT_ID}-mlops-aula`** (com sufixo `-mlops-aula`) contém artefatos desta aula. Confira o sufixo do nome antes de executar qualquer `rm -r`.

- [ ] Versões do modelo deletadas
- [ ] Modelo `rf-preco-imoveis` deletado
- [ ] Objetos em `gs://${PROJECT_ID}-mlops-aula/models/` removidos
- [ ] `${PROJECT_ID}-aula-pdm` e `aula_pdm` **preservados**

---

## 6. Teardown automatizado

O script [`scripts/30_teardown.sh`](scripts/30_teardown.sh) executa os passos 1 a 4 na mesma ordem, de forma idempotente (pode ser rodado mais de uma vez sem erro).

```bash
export PROJECT_ID="SEU_PROJECT_ID"
export REGION="us-central1"

bash scripts/30_teardown.sh
```

> O script é uma conveniência de autoestudo. **Na aula, faça o teardown pelo console**, para que os alunos vejam cada recurso desaparecendo e entendam o que estão apagando. Depois confirme com a varredura da seção 9.

---

## 7. Budgets e alertas de faturamento

Um budget **não bloqueia gastos** — ele **avisa**. Ainda assim, é a diferença entre descobrir um endpoint esquecido em dois dias ou em dois meses.

### 7.1 Console

1. Console → **Billing** (*Faturamento*) → selecionar a conta de faturamento.
2. Menu lateral → **Budgets & alerts** (*Orçamentos e alertas*).
3. **Create budget** (*Criar orçamento*).
4. **Scope** (*Escopo*): restringir ao projeto `SEU_PROJECT_ID`.
5. **Amount** (*Valor*): um valor baixo e realista para a atividade — por exemplo **US$ 50**.
6. **Actions / Thresholds** (*Regras de limite*): marcar alertas em **50%**, **90%** e **100%**.
7. Confirmar os destinatários dos e-mails de alerta e salvar.

### 7.2 gcloud

```bash
gcloud billing budgets create \
  --billing-account=SEU_BILLING_ACCOUNT_ID \
  --display-name="aula-mlops-vertex" \
  --budget-amount=50USD \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0
```

Para restringir ao projeto da aula, acrescente o filtro de projeto:

```bash
gcloud billing budgets create \
  --billing-account=SEU_BILLING_ACCOUNT_ID \
  --display-name="aula-mlops-vertex" \
  --budget-amount=50USD \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0 \
  --filter-projects="projects/SEU_PROJECT_ID"
```

Listar e conferir:

```bash
gcloud billing budgets list --billing-account=SEU_BILLING_ACCOUNT_ID
```

> **O alerta avisa, não corta.** Nenhum threshold interrompe recursos automaticamente. O budget é um detector de fumaça, não um extintor — o extintor é este checklist.

---

## 8. Free Trial como rede de segurança

Quem está no **Free Trial** do Google Cloud tem **US$ 300 em créditos, válidos por 90 dias**. Dois pontos importantes para a turma:

- **Ao fim do período de teste, não há cobrança automática.** Os recursos são suspensos e é preciso fazer o upgrade para uma conta paga de forma explícita. Isso é uma proteção real contra a fatura surpresa.
- **Os créditos são consumidos igualmente.** Um endpoint esquecido queima crédito todo dia, e crédito queimado não volta. A rede de segurança evita a cobrança, não o desperdício.

Onde conferir: Console → **Billing** → **Overview**, no painel de créditos do Free Trial (dias restantes e saldo).

---

## 9. Confira que nada ficou ligado

> **VARREDURA FINAL — percorra os cinco itens antes de fechar o console**
>
> Confirme a região **`us-central1`** em cada tela.
>
> | # | Onde olhar | O que você deve ver |
> |---|---|---|
> | 1 | Vertex AI → Online prediction → **Endpoints** | Lista **vazia** (nenhum `rf-preco-imoveis-endpoint`) |
> | 2 | Vertex AI → Colab Enterprise → **Runtimes** · e Workbench → **Instances** | **Nenhum** runtime ativo, **nenhuma** instância ligada |
> | 3 | Vertex AI → Experiments → **TensorBoard instances** | Lista **vazia** (é o que se espera com `experiment_tensorboard=False`; confira mesmo assim) |
> | 4 | Vertex AI → **Model Registry** | Sem `rf-preco-imoveis` |
> | 5 | Cloud Storage → **`${PROJECT_ID}-mlops-aula`** | Sem os objetos em `models/` |
>
> E, por último, a verificação inversa:
>
> | Manter | O que **deve continuar existindo** |
> |---|---|
> | Sim | Bucket **`${PROJECT_ID}-aula-pdm`** |
> | Sim | Dataset **`aula_pdm`** e a tabela gold |
> | Sim | O **experimento** `preco-imoveis-rf` (metadados de runs não geram custo relevante e servem de evidência da entrega) |

Conferência rápida por linha de comando:

```bash
gcloud ai endpoints list --project="${PROJECT_ID}" --region="${REGION}"
gcloud ai models     list --project="${PROJECT_ID}" --region="${REGION}"
gcloud ai tensorboards list --project="${PROJECT_ID}" --region="${REGION}"
gcloud storage ls "gs://${PROJECT_ID}-mlops-aula/"
```

As três primeiras devem voltar vazias para os recursos da aula.

---

## 10. Retomando os conceitos

| Recurso | Cobra quando | Encerra como |
|---|---|---|
| Vertex AI **Experiments** (métricas-resumo) | Praticamente não cobra — desde que o `init` use `experiment_tensorboard=False` e nenhum TensorBoard seja criado | Pode ficar |
| **Model Registry** | Registrar é **grátis**; paga-se o artefato no GCS | Deletar versões e modelo |
| **Endpoint** com modelo implantado | **Por node-hora, 24/7, mesmo ocioso** | **Undeploy → delete** |
| **Runtime** do notebook | Enquanto ativo (auto-shutdown ~180 min) | Deletar o runtime |
| **TensorBoard** | Por GiB armazenado/mês | Deletar a instância |

Volte ao [`README.md`](README.md) para o índice completo, ou ao [`roteiro-condutor.md`](roteiro-condutor.md) para ver como este bloco se encaixa nos minutos 45–55 da aula.
