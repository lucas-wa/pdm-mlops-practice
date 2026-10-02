# 05 — Encerramento e custos

O documento mais importante da aula: encerra os recursos criados, **na ordem correta**, e configura o
acompanhamento do consumo dos créditos.

> **A turma usa créditos educacionais do Google Cloud — não há cobrança no cartão de ninguém.** Os
> créditos, porém, são **finitos**: tudo o que fica ligado consome saldo que faria falta nas próximas
> atividades. Encerrar é **higiene de ambiente**, e faz parte da entrega.

> **Execute este checklist ao final da aula, com a turma, item a item.**
>
> O recurso que mais consome créditos — o **Endpoint com modelo implantado** — consome **por node-hora,
> 24 horas por dia, mesmo sem nenhuma requisição**. Ele não desliga sozinho.

---

## 1. Ordem de encerramento (do que mais consome ao que menos consome)

| # | Recurso | Por que consome créditos | Urgência |
|---|---|---|---|
| 1 | **Endpoint com modelo implantado** | Nós tarifados **por hora, 24/7**, mesmo ociosos. Não desliga sozinho | **Crítica** |
| 2 | **Runtime do notebook** (BigQuery Studio / Colab Enterprise; ou VM do Workbench) | Consome enquanto está ativo | Alta |
| 3 | **Instância de TensorBoard** | Armazenamento, na ordem de **US$ 10/GiB/mês**. Nesta aula **não criamos nenhuma porque passamos `experiment_tensorboard=False`** no `aiplatform.init(...)` — sem esse parâmetro o SDK criaria uma sozinho | Média (se existir) |
| 4 | **Modelo, versões e objetos no GCS** | Armazenamento, consumo baixo | Baixa |

> **Dependência que quebra o teardown:** não é possível deletar um modelo ainda **implantado** em um
> endpoint. É preciso fazer o **undeploy** primeiro — por isso o passo 1 vem antes do passo 4.

> **Registrar modelo no Model Registry é GRATUITO.** Consome crédito o artefato no GCS (centavos) e,
> principalmente, o **endpoint**.

---

## 2. Passo 1 — Undeploy e deleção do endpoint (o que mais consome)

### 2.1 Undeploy do modelo

1. Console → **Vertex AI** → **Online prediction** → **Endpoints**.
2. Confirmar a região **`us-central1`**.
3. Clicar em **`rf-preco-imoveis-endpoint`**.
4. Na lista de modelos implantados, menu de três pontos da linha do modelo → **Undeploy model**.
5. Confirmar e **aguardar a conclusão**. Enquanto o undeploy não terminar, os nós continuam consumindo.

### 2.2 Deleção do endpoint

1. Voltar à lista de **Endpoints**.
2. Marcar **`rf-preco-imoveis-endpoint`** (agora sem modelos implantados).
3. **Delete** e confirmar.

- [ ] Undeploy concluído
- [ ] Endpoint deletado
- [ ] Lista de Endpoints em `us-central1` está **vazia**

---

## 3. Passo 2 — Runtime do notebook

### 3.1 BigQuery Studio / Colab Enterprise (ambiente desta aula)

Há auto-desligamento por inatividade (~**180 minutos**), mas **apagar o runtime é o que garante** o
encerramento imediato.

1. Console → **Vertex AI** → **Colab Enterprise** → **Runtimes**.
2. Confirmar a região **`us-central1`**.
3. Selecionar o runtime da aula → **Delete**.

Apenas desconectar o notebook **não** encerra o runtime.

### 3.2 Vertex AI Workbench (só se alguém usou)

Workbench é uma **VM**: consome créditos enquanto ligada, mesmo sem notebook aberto.

1. Console → **Vertex AI** → **Workbench** → **Instances**.
2. **Stop** — interrompe a computação.
3. **Delete** — encerra também o disco.

- [ ] Runtime do BigQuery Studio / Colab Enterprise deletado
- [ ] Instância do Workbench parada e deletada (se houver)

---

## 4. Passo 3 — TensorBoard (verificação)

> **Nesta aula NÃO criamos nenhuma instância de TensorBoard — porque passamos
> `experiment_tensorboard=False` no `aiplatform.init(...)`.** As métricas-resumo do Experiments (`mae`,
> `mae_baseline`) não exigem TensorBoard.

**Sem esse parâmetro, o SDK cria uma instância *Default Tensorboard* automaticamente** ao associar o
experimento. Por isso este passo é uma **verificação**: se alguém rodou o `init` sem o parâmetro, a
instância está lá, consumindo por **armazenamento** (na ordem de US$ 10/GiB/mês — confirme o valor atual
no pricing ao vivo).

1. Console → **Vertex AI** → **Experiments** → aba **TensorBoard instances**.
2. Confirmar a região **`us-central1`**.
3. Se houver alguma instância, selecionar e **Delete**.

- [ ] Lista de TensorBoard instances verificada e **vazia**

---

## 5. Passo 4 — Modelo, versões e objetos no GCS

### 5.1 Versões e modelo no Model Registry

1. Console → **Vertex AI** → **Model Registry**, região **`us-central1`**.
2. Clicar em **`rf-preco-imoveis`** → aba de **versões**.
3. Deletar as **versões** (três pontos → *Delete version*) e depois o **modelo**.

> Se a deleção falhar com erro de modelo em uso, **o undeploy do passo 1 não foi concluído**. Volte à
> seção 2.

### 5.2 Objetos no bucket da aula

1. Console → **Cloud Storage** → **Buckets** → **`${PROJECT_ID}-mlops-aula`**.
2. Entrar em `models/` e excluir os objetos da aula.

O SDK usa o mesmo bucket como **staging** e pode ter criado pastas auxiliares. Como
`${PROJECT_ID}-mlops-aula` é dedicado a esta aula, é seguro esvaziá-lo por inteiro.

> **NÃO APAGUE A INFRAESTRUTURA COMPARTILHADA**
>
> - O bucket **`${PROJECT_ID}-aula-pdm`** é das aulas anteriores e será usado no Dia 2. **Não apague,
>   não esvazie.**
> - O dataset **`aula_pdm`** e a **tabela gold** também permanecem. **Não apague.**
> - Apagar por engano é **irreversível** e derruba o material das próximas aulas.
>
> Só o bucket com sufixo **`-mlops-aula`** contém artefatos desta aula. Confira o sufixo antes de
> apagar qualquer coisa.

- [ ] Versões do modelo deletadas
- [ ] Modelo `rf-preco-imoveis` deletado
- [ ] Objetos em `gs://${PROJECT_ID}-mlops-aula/models/` removidos
- [ ] `${PROJECT_ID}-aula-pdm` e `aula_pdm` **preservados**

---

## 6. Budgets e alertas — acompanhar o consumo dos créditos

Como a turma usa créditos educacionais, o budget não evita cobrança: ele **acompanha quanto dos créditos
já foi consumido** e avisa quando algo consome mais que o esperado. Um budget **não bloqueia nada**.

1. Console → **Billing** → selecionar a conta de faturamento.
2. Menu lateral → **Budgets & alerts** → **Create budget**.
3. **Scope**: restringir ao projeto `SEU_PROJECT_ID`.
4. **Amount**: um valor baixo e realista — por exemplo **US$ 50**.
5. **Actions / Thresholds**: alertas em **50%**, **90%** e **100%**.
6. Confirmar os destinatários dos e-mails e salvar.

> **O alerta avisa, não corta.** O budget é um detector de fumaça; o extintor é este checklist.

---

## 7. Créditos educacionais — o que eles cobrem

- **Não há cobrança no cartão de ninguém.** O consumo sai do saldo de créditos do projeto. Não existe
  "fatura surpresa" nesta atividade.
- **Os créditos são finitos e não voltam.** Um endpoint esquecido queima crédito todo dia, e crédito
  queimado não volta ao saldo. Por isso o teardown vale: é higiene de ambiente.

Onde conferir: Console → **Billing** → **Overview**, no painel de créditos (saldo e validade).

---

## 8. Confira que nada ficou ligado

> **VARREDURA FINAL — percorra os cinco itens antes de fechar o console**
>
> Confirme a região **`us-central1`** em cada tela.
>
> | # | Onde olhar | O que você deve ver |
> |---|---|---|
> | 1 | Vertex AI → Online prediction → **Endpoints** | Lista **vazia** (nenhum `rf-preco-imoveis-endpoint`) |
> | 2 | Vertex AI → Colab Enterprise → **Runtimes** · e Workbench → **Instances** | **Nenhum** runtime ativo, **nenhuma** instância ligada |
> | 3 | Vertex AI → Experiments → **TensorBoard instances** | Lista **vazia** (esperado com `experiment_tensorboard=False`; confira mesmo assim) |
> | 4 | Vertex AI → **Model Registry** | Sem `rf-preco-imoveis` |
> | 5 | Cloud Storage → **`${PROJECT_ID}-mlops-aula`** | Sem os objetos em `models/` |
>
> E a verificação inversa:
>
> | Manter | O que **deve continuar existindo** |
> |---|---|
> | Sim | Bucket **`${PROJECT_ID}-aula-pdm`** |
> | Sim | Dataset **`aula_pdm`** e a tabela gold |
> | Sim | O **experimento** `preco-imoveis-rf` (metadados de runs não geram custo relevante e servem de evidência da entrega) |

---

## 9. Retomando os conceitos

| Recurso | Consome créditos quando | Encerra como |
|---|---|---|
| Vertex AI **Experiments** (métricas-resumo) | Praticamente não consome — desde que o `init` use `experiment_tensorboard=False` | Pode ficar |
| **Model Registry** | Registrar é **grátis**; consome-se só o artefato no GCS | Deletar versões e modelo |
| **Endpoint** com modelo implantado | **Por node-hora, 24/7, mesmo ocioso** | **Undeploy → delete** |
| **Runtime** do notebook | Enquanto ativo (auto-shutdown ~180 min) | Deletar o runtime |
| **TensorBoard** | Por GiB armazenado/mês | Deletar a instância |

---

Equivalentes em CLI e IaC: veja [`gcloud/README.md`](gcloud/README.md) e [`terraform/README.md`](terraform/README.md).
O script [`gcloud/30_teardown.sh`](gcloud/30_teardown.sh) executa os passos 1 a 4 na mesma ordem, de
forma idempotente — mas **na aula faça o teardown pelo console**, para que os alunos vejam cada recurso
desaparecendo.

Volte ao [`README.md`](README.md) para o índice, ou ao [`roteiro-condutor.md`](roteiro-condutor.md) para
ver como este bloco se encaixa nos minutos 45–55.
