# Roteiro do condutor — aula ao vivo no console (~60 min)

Roteiro minuto a minuto para o docente conduzir a aula **Introdução ao MLOps no GCP: Experiments + Model Registry no Vertex AI** pelo console do Google Cloud, com o notebook aberto no BigQuery Studio.

Material de apoio: [`README.md`](README.md) · [`00-pre-requisitos-e-gold.md`](00-pre-requisitos-e-gold.md) · [`02-treino-e-experiments.md`](02-treino-e-experiments.md) · [`03-model-registry.md`](03-model-registry.md) · [`04-deploy-endpoint.md`](04-deploy-endpoint.md) · [`05-encerramento-custos.md`](05-encerramento-custos.md)

---

## Antes de entrar na sala

- [ ] Ambiente do [`00-pre-requisitos-e-gold.md`](00-pre-requisitos-e-gold.md) validado: APIs, IAM, bucket `${PROJECT_ID}-mlops-aula`, dataset `aula_pdm`.
- [ ] **Nome real da tabela gold** confirmado e substituído no lugar de `GOLD_TABLE` no notebook.
- [ ] Notebook [`notebooks/treino_experiments_registry.ipynb`](notebooks/treino_experiments_registry.ipynb) **executado de ponta a ponta no ensaio**, com tempo de cada célula anotado.
- [ ] **Endpoint de referência já provisionado e respondendo** (contingência — ver seção de contingências).
- [ ] Rótulos do console conferidos no dia (rebrand "Gemini Enterprise Agent Platform" na documentação vs. "Vertex AI" no console).
- [ ] Runtime do BigQuery Studio **já ligado e aquecido** — subir runtime ao vivo custa minutos que o roteiro não tem.
- [ ] Abas do navegador pré-abertas: BigQuery Studio · Vertex AI Experiments · Model Registry · Online prediction → Endpoints · Billing → Budgets & alerts.
- [ ] Budget do projeto já criado, para mostrar na tela sem precisar configurar do zero.

> **Regra de ouro do tempo.** O deploy do endpoint leva de 10 a 20 minutos e **não acelera**. O roteiro abaixo dispara o deploy assim que o modelo está registrado e usa o tempo de provisionamento para explicar Registry e Experiments. Se você esperar o deploy terminar parado, a aula não fecha em 1 hora.

---

## 00–05 min · Contexto e objetivos

**Objetivo do bloco:** a turma entende o caminho completo antes de ver a primeira linha de código.

| Ação | Como conduzir |
|---|---|
| Retomar de onde paramos | Mostrar a tabela gold no BigQuery Studio. "Vocês construíram isso. Hoje ela vira um modelo que responde por HTTP." |
| Enunciar a pergunta | Prever `preco` (preço **de anúncio**) a partir das características do imóvel |
| Desenhar o caminho | gold → treino → **Experiments** (rastrear) → **Model Registry** (versionar) → **Endpoint** (servir) |
| Definir MLOps em uma frase | "Fazer com que outra pessoa consiga reproduzir, auditar e reverter o que você treinou." |
| Avisar sobre custos | Apontar para [`05-encerramento-custos.md`](05-encerramento-custos.md) **agora**, não no final. "Vamos criar um endpoint que cobra por hora. Nos últimos 10 minutos, desligamos tudo juntos." |

> **Checkpoint — o que os alunos devem ter na tela**
>
> BigQuery Studio aberto, dataset `aula_pdm` expandido, tabela gold visível no Explorer, notebook `treino_experiments_registry.ipynb` aberto e com o runtime conectado.

---

## 05–20 min · Treino + Vertex AI Experiments

**Objetivo do bloco:** um modelo treinado, comparado com o baseline, e **duas runs** visíveis no console.

| Tempo | Ação | Fala-chave |
|---|---|---|
| 05–08 | Ler a gold e aplicar o recorte | Mostrar as colunas escolhidas e **dizer em voz alta o que foi excluído** (`preco_fmt`, preço/m²) e por quê |
| 08–10 | Dedup e separação | "Mesmo imóvel não pode estar em treino e teste. Senão o modelo acerta porque decorou." |
| 10–13 | Baseline e treino | Rodar o baseline da mediana **antes** do modelo. O número do baseline precisa estar na tela quando o MAE do RF aparecer |
| 13–16 | Run 1 no Experiments | `preco-imoveis-rf`, logar `params` e `metrics` (`mae`, `mae_baseline`) |
| 16–19 | Run 2 variando um hiperparâmetro | Mudar **um** parâmetro — no notebook é só o `max_depth` (12 → 24), com `n_estimators=200` nos dois runs. Um só — a comparação precisa ser legível |
| 19–20 | Comparar no console | Vertex AI → **Experiments** → `preco-imoveis-rf` → selecionar as duas runs → **Compare** |

**Conceito a fixar:** o valor do Experiments não é guardar métricas — é conseguir responder "por que esta versão é melhor que aquela?" três semanas depois, sem depender da memória de ninguém.

> **Se o treino demorar mais que o previsto:** reduza `n_estimators` na hora. O ponto pedagógico é a comparação entre runs, não a qualidade do modelo.

> **Checkpoint — o que os alunos devem ter na tela**
>
> Notebook com MAE do modelo e MAE do baseline impressos, e a tela de comparação do Experiments mostrando as **duas runs** lado a lado com parâmetros e métricas.

---

## 20–30 min · Model Registry

**Objetivo do bloco:** modelo `rf-preco-imoveis` registrado, com uma segunda versão e o alias `default`.

| Tempo | Ação | Fala-chave |
|---|---|---|
| 20–23 | Salvar o artefato | `model.joblib` em `gs://${PROJECT_ID}-mlops-aula/models/rf/`. Enfatizar: o nome do arquivo **precisa ser `model.joblib`** — é o que o container de serving procura |
| 23–26 | Registrar o modelo | Display name `rf-preco-imoveis`, `artifact_uri` apontando para o **diretório** (não para o arquivo), container de serving scikit-learn |
| 26–27 | **Disparar o deploy agora** | Ver bloco 30–45. **Não espere** — inicie o deploy neste minuto e continue explicando |
| 27–29 | Nova versão | Registrar uma segunda versão com `parent_model`, mostrar `version_aliases` e `default` |
| 29–30 | Mostrar no console | Vertex AI → **Model Registry** → `rf-preco-imoveis` → aba de versões |

**Conceito a fixar:** registrar um modelo é **gratuito**. O que separa "treinei" de "publiquei" é uma decisão explícita — o alias `default` é essa decisão, escrita de forma que um serviço consiga ler.

> **Antecipe o deploy.** O comando de deploy do bloco seguinte deve ser disparado por volta do minuto 26. A partir daí, tudo o que você fala sobre versões e aliases roda em paralelo com o provisionamento.

> **Checkpoint — o que os alunos devem ter na tela**
>
> Model Registry com `rf-preco-imoveis` listado, duas versões visíveis, e o alias `default` apontando para a versão escolhida. Deploy em andamento na aba de Endpoints.

---

## 30–45 min · Deploy em Endpoint e predição online

**Objetivo do bloco:** `rf-preco-imoveis-endpoint` respondendo a uma predição real.

| Tempo | Ação | Fala-chave |
|---|---|---|
| ~26 | (já disparado) Criar endpoint + deploy | `rf-preco-imoveis-endpoint`, máquina pequena, **1 réplica** |
| 30–36 | Explicar **enquanto provisiona** | O que é um endpoint, o que é uma réplica, por que isso custa por hora mesmo sem tráfego. Mostrar a tela de progresso |
| 36–40 | Ordem canônica das features | Escrever na tela: `[area_util, area_total, quartos, banheiros, garagens]`. "Trocar a ordem não dá erro. Dá resposta errada." |
| 40–43 | Predição online | Enviar o payload e ler o preço estimado. Conferir **qual versão do modelo** respondeu |
| 43–45 | Sanidade da resposta | Comparar a predição com a mediana do baseline. "Esse número faz sentido para um imóvel assim?" |

**Conceito a fixar:** este é o ponto em que o modelo deixa de ser um arquivo e vira um serviço — e o momento exato em que ele começa a custar dinheiro continuamente.

> **Checkpoint — o que os alunos devem ter na tela**
>
> Endpoint `rf-preco-imoveis-endpoint` com status ativo e o modelo implantado, e uma resposta de `/predict` com um valor de preço plausível.

### Contingências deste bloco

| Situação | O que fazer |
|---|---|
| **Deploy não concluiu no tempo** | Demonstrar a predição no **endpoint de referência pré-provisionado**. Deixar claro que ele **não conta como entrega do grupo** — o deploy do grupo fica registrado como pendente |
| **Erro de unpickle no serving** | Incompatibilidade entre a versão do scikit-learn do treino e a do container. Cair para o endpoint de referência e tratar como caso de estudo: "por que fixar versões é parte do MLOps" |
| **Predição com valor absurdo** | Quase sempre é ordem de features trocada no payload. Ótimo momento didático — mostre o erro em vez de escondê-lo |
| **Tempo estourou** | Pule a predição ao vivo, mostre o endpoint de referência em 2 minutos e **vá direto para o encerramento**. O bloco 45–55 não pode ser cortado |

---

## 45–55 min · Encerramento e custos, ao vivo

**Objetivo do bloco:** nenhum aluno sai da sala com recurso ligado.

Conduzir **junto com a turma**, item a item, seguindo [`05-encerramento-custos.md`](05-encerramento-custos.md). Todos executam ao mesmo tempo, na mesma ordem.

| Tempo | Ação |
|---|---|
| 45–47 | **Undeploy** do modelo no endpoint, depois **deletar o endpoint**. Explicar por que esta é a ordem: não se apaga o modelo com ele implantado |
| 47–49 | **Apagar o runtime** do notebook (BigQuery Studio / Colab Enterprise). Se alguém usou Workbench, **Stop** e **Delete** da instância |
| 49–50 | **TensorBoard**: nesta aula **não criamos nenhuma instância porque o `aiplatform.init(...)` passa `experiment_tensorboard=False`**. Deixar claro que, **sem esse parâmetro, o SDK cria uma instância *Default Tensorboard* sozinho** ao associar o experimento — por isso conferimos a lista mesmo assim. Há cobrança por armazenamento (na ordem de US$ 10/GiB/mês — confirmar o valor no pricing ao vivo) |
| 50–52 | Deletar **versões e modelo** e os **objetos no GCS da aula** (`gs://${PROJECT_ID}-mlops-aula/`) |
| 52–54 | **Budget e alertas**: mostrar Billing → **Budgets & alerts** na tela; explicar que o alerta avisa, não bloqueia |
| 54–55 | **Varredura final**: percorrer a caixa "Confira que nada ficou ligado" do [`05-encerramento-custos.md`](05-encerramento-custos.md) |

> **Reforço obrigatório em voz alta**
>
> **NÃO apagar** o bucket compartilhado `${PROJECT_ID}-aula-pdm` nem o dataset `aula_pdm`. São infraestrutura das aulas anteriores e serão usados no Dia 2. Apagar é irreversível.

> **Free Trial como rede de segurança.** Quem está no Free Trial (US$ 300 / 90 dias) **não é cobrado automaticamente** quando o período expira. É uma proteção real, mas não substitui o teardown: os créditos são consumidos do mesmo jeito.

> **Checkpoint — o que os alunos devem ter na tela**
>
> Lista de Endpoints **vazia**, lista de runtimes **vazia**, Model Registry sem os modelos da aula, bucket da aula sem os objetos — e o bucket `${PROJECT_ID}-aula-pdm` **intacto**.

---

## 55–60 min · Fechamento e ponte para o Dia 2

| Tempo | Ação |
|---|---|
| 55–57 | Conferir entregas: MAE comparado ao baseline, 2 runs no Experiments, modelo registrado com versão, predição online obtida (ou registrada como pendente) |
| 57–59 | Amarrar o conceito: rastrear (Experiments) → versionar (Registry) → servir (Endpoint). "Hoje fizemos isso **na mão**, clicando." |
| 59–60 | Ponte para o Dia 2: **orquestração**. "Tudo o que clicamos hoje vira etapa de pipeline: preparar dados, treinar, avaliar, aprovar por métrica e publicar — com o serviço atual preservado quando o candidato for reprovado." |

**Entregas do aluno:** notebook executado com MAE e baseline; duas runs no experimento `preco-imoveis-rf`; modelo `rf-preco-imoveis` registrado; predição online do endpoint (ou registro explícito de deploy pendente); **checklist de encerramento concluído**.

---

## Flexibilização do tempo

Este roteiro cabe em **60 minutos** quando o ensaio foi feito e o deploy é antecipado. Na prática:

| Cenário | Duração | Ajuste |
|---|---|---|
| **Roteiro completo, turma acompanhando bem** | 60 min | Sem ajuste |
| **Com perguntas e prática guiada** | **75–90 min** | Esticar os blocos 05–20 e 30–45; manter 45–55 intacto |
| ***Fallback* rápido — sem deploy** | ~40 min | Percorrer treino → Experiments → Registry. Demonstrar a predição no **endpoint de referência** em 3 minutos e ir para o encerramento |
| **Turma travada no ambiente** | variável | Usar o projeto do docente como referência única na tela; alunos acompanham sem executar, e a prática vira tarefa assistida |

**O que nunca cortar:** o bloco **45–55 (encerramento e custos)**. É o único bloco cuja ausência gera consequência financeira para os alunos. Se o tempo apertar, corte a segunda versão do modelo, corte a segunda run, corte a predição ao vivo — o teardown fica.

**O que cortar primeiro, nesta ordem:**

1. Sanidade da resposta do endpoint (43–45).
2. Segunda versão do modelo no Registry (27–29).
3. Predição ao vivo, substituída pelo endpoint de referência (40–43).
4. Segunda run do Experiments (16–19) — mas isso enfraquece bastante o bloco de comparação.

---

## Resumo dos checkpoints

| Momento | O aluno deve ter na tela |
|---|---|
| 05 min | BigQuery Studio com `aula_pdm` e o notebook conectado ao runtime |
| 20 min | MAE do modelo e do baseline impressos; 2 runs comparadas no Experiments |
| 30 min | `rf-preco-imoveis` no Model Registry com 2 versões e alias `default`; deploy em andamento |
| 45 min | `rf-preco-imoveis-endpoint` ativo e resposta de `/predict` com valor plausível |
| 55 min | Endpoints e runtimes **vazios**; `${PROJECT_ID}-aula-pdm` preservado |
