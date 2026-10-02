# Introdução ao MLOps no GCP: Experiments + Model Registry no Vertex AI

Tutorial de aproximadamente 1 hora, conduzido ao vivo pelo console do Google Cloud, que parte da camada **gold** de anúncios de imóveis (BigQuery, dataset `aula_pdm`, região `us-central1`) e chega a um modelo treinado, rastreado, versionado e servido em um endpoint de predição online.

> **AVISO DE CONSUMO DE CRÉDITOS — LEIA ANTES DE COMEÇAR**
>
> A turma usa **créditos educacionais do Google Cloud**: **não há cobrança no cartão de ninguém**. Os créditos, porém, são **finitos**.
>
> Esta aula cria recursos que **consomem créditos por hora enquanto existirem**, mesmo sem nenhum tráfego. O principal deles é o **Endpoint com modelo implantado** (`rf-preco-imoveis-endpoint`): os nós ficam ligados 24/7 até você fazer o *undeploy* e apagar o endpoint.
>
> **Ao terminar a aula, execute o checklist de encerramento:** [`05-encerramento-custos.md`](05-encerramento-custos.md). É higiene de ambiente — mantém o saldo de créditos disponível para as próximas atividades.
>
> O encerramento é feito **ao vivo, junto com a turma**, nos últimos minutos da aula. Não deixe para depois.

---

## 1. O que é MLOps, em três frases

**Vertex AI Experiments** guarda o histórico de cada treino — parâmetros, métricas e artefatos — para que duas execuções possam ser comparadas em vez de discutidas de memória. **Vertex AI Model Registry** guarda o modelo treinado como um objeto versionado, com identidade e alias, separando "treinei um modelo" de "este é o modelo oficial". **Vertex AI Endpoint** publica uma versão registrada atrás de uma API HTTP, transformando o artefato em um serviço que responde a predições.

MLOps é, na prática, a disciplina que liga essas três coisas: **rastrear** o que foi feito, **versionar** o que foi produzido e **publicar** o que foi aprovado — de forma que outra pessoa consiga reproduzir, auditar e reverter.

## 2. Objetivos de aprendizagem

Ao final da aula, o aluno deve ser capaz de:

1. Ler a camada gold do BigQuery e montar um conjunto de treino/validação/teste respeitando o contrato de dados (dedup por imóvel, exclusão de colunas que vazam o alvo).
2. Treinar um pipeline scikit-learn (`RandomForestRegressor`) para prever `preco` e comparar seu **MAE** com o **baseline da mediana**.
3. Registrar parâmetros e métricas de **duas execuções** no experimento `preco-imoveis-rf` e compará-las no console do Vertex AI Experiments.
4. Registrar o modelo como `rf-preco-imoveis` no Model Registry, criar uma **nova versão** e entender o papel do alias `default`.
5. Implantar a versão em um **Endpoint** (`rf-preco-imoveis-endpoint`) e obter uma **predição online** com o payload na ordem canônica de features.
6. Executar o **checklist de encerramento** e explicar qual recurso consome quanto crédito.

## 3. Pré-requisitos

| Item | Detalhe |
|---|---|
| Projeto GCP | Um projeto próprio com **faturamento (billing) ativo**, vinculado aos **créditos educacionais** da disciplina. |
| Acessos | Cada aluno é **`Owner` do próprio projeto** — `roles/owner` já cobre tudo (Vertex AI, Storage, BigQuery, habilitar APIs) e **não é preciso conceder nenhum papel**. Os papéis mínimos em [`01-setup-gcp.md`](01-setup-gcp.md) são referência para projeto compartilhado. |
| Região | Todos os recursos em **`us-central1`**, para casar com o dataset do BigQuery. |
| Camada gold | Tabela gold de anúncios já existente no dataset `aula_pdm`, com nome e schema **confirmados antes da aula**. |
| Ambiente | **BigQuery Studio** (runtime Colab Enterprise) — não é necessário instalar nada na máquina local. |
| Conhecimento | Python básico, pandas e noções de treino/validação/teste. |

O detalhamento dos pré-requisitos e o **contrato de dados** estão em [`00-pre-requisitos-e-gold.md`](00-pre-requisitos-e-gold.md). Leia antes da aula.

## 4. Como esta aula é conduzida

- **Ao vivo, pelo console.** Todo o caminho demonstrado pelo docente usa a interface do Google Cloud (Vertex AI → Experiments, Model Registry, Online prediction) e o notebook no BigQuery Studio. É o caminho que os alunos acompanham na tela.
- **gcloud e Terraform são material de autoestudo.** Os scripts em [`scripts/`](scripts/) e o módulo em [`terraform/`](terraform/) reproduzem o mesmo resultado por linha de comando e por infraestrutura como código. Eles existem para o aluno comparar os três caminhos depois da aula — **não** serão executados durante o encontro.
- **Nem tudo tem equivalente em IaC.** Experiments, registro de modelo e deploy em endpoint **não são gerenciados pelo Terraform**; ficam em SDK, gcloud ou console. Isso está explicitado em [`01-setup-gcp.md`](01-setup-gcp.md).

> **Nota sobre nomes no console**
>
> A documentação do Google está em processo de rebrand e aparece como **"Gemini Enterprise Agent Platform"** em várias páginas, enquanto o **console ainda exibe "Vertex AI"**. Os rótulos usados aqui seguem o console. Confirme os nomes ao vivo antes da aula — menus podem ter mudado de lugar.

## 5. Convenções de nomes

Estes nomes são usados **exatamente assim** em todos os arquivos, notebooks e scripts desta aula.

| Recurso | Valor |
|---|---|
| Região | `us-central1` |
| Projeto (placeholder) | `SEU_PROJECT_ID` |
| Conta de faturamento (placeholder) | `SEU_BILLING_ACCOUNT_ID` |
| Bucket **da aula** (artefatos do modelo) | `${PROJECT_ID}-mlops-aula` |
| Bucket **compartilhado** (aulas anteriores — **não apagar**) | `${PROJECT_ID}-aula-pdm` |
| Dataset BigQuery | `aula_pdm` |
| Tabela gold (placeholder) | `GOLD_TABLE` |
| Experiment | `preco-imoveis-rf` |
| Modelo no Registry | `rf-preco-imoveis` |
| Endpoint | `rf-preco-imoveis-endpoint` |
| Ordem canônica de features (payload `/predict`) | `[area_util, area_total, quartos, banheiros, garagens]` |

> **Atenção ao bucket.** `${PROJECT_ID}-mlops-aula` é criado **para esta aula** e pode ser esvaziado no encerramento. `${PROJECT_ID}-aula-pdm` é a infraestrutura **compartilhada** das aulas anteriores e **não deve ser apagada**.

## 6. Agenda (~1 hora)

| Tempo | Bloco | Resultado esperado |
|---|---|---|
| 00–05 | Contexto e objetivos | Turma entende o caminho gold → modelo rastreado → versionado → servido |
| 05–20 | Treino + Experiments | Modelo treinado, MAE comparado ao baseline, 2 runs comparadas no console |
| 20–30 | Model Registry | `model.joblib` no GCS, modelo `rf-preco-imoveis` registrado, nova versão + alias |
| 30–45 | Deploy em Endpoint | Endpoint respondendo `/predict` (deploy **iniciado cedo**, em paralelo) |
| 45–55 | Encerramento e consumo de créditos | Teardown executado ao vivo; budget configurado |
| 55–60 | Fechamento | Entregas conferidas e ponte para o Dia 2 (orquestração/pipelines) |

Com o deploy em endpoint, a aula pode esticar para **75–90 minutos**. O caminho **sem deploy** (treino → Experiments → Registry) é o *fallback* rápido quando o tempo apertar. Detalhes e contingências no [`roteiro-condutor.md`](roteiro-condutor.md).

## 7. Índice do material

### Documentos da aula

| Arquivo | Conteúdo |
|---|---|
| [`00-pre-requisitos-e-gold.md`](00-pre-requisitos-e-gold.md) | Checklist de pré-requisitos, contrato de dados, anti-vazamento, dedup, baseline e como confirmar o schema da gold |
| [`01-setup-gcp.md`](01-setup-gcp.md) | APIs, IAM, bucket e dataset — Console, gcloud e Terraform lado a lado |
| [`02-treino-e-experiments.md`](02-treino-e-experiments.md) | Leitura da gold, treino do RandomForest, baseline, MAE e registro das runs no Experiments |
| [`03-model-registry.md`](03-model-registry.md) | Salvar `model.joblib` no GCS, registrar `rf-preco-imoveis`, versões e aliases |
| [`04-deploy-endpoint.md`](04-deploy-endpoint.md) | Criar `rf-preco-imoveis-endpoint`, implantar o modelo e fazer predição online |
| [`05-encerramento-custos.md`](05-encerramento-custos.md) | **Checklist de teardown**, budgets e alertas, créditos educacionais |
| [`roteiro-condutor.md`](roteiro-condutor.md) | Roteiro minuto a minuto para o docente conduzir no console |

### Código e automação

| Caminho | Conteúdo |
|---|---|
| [`notebooks/treino_experiments_registry.ipynb`](notebooks/treino_experiments_registry.ipynb) | Notebook executável de ponta a ponta no BigQuery Studio |
| [`terraform/`](terraform/) | APIs, bucket e dataset como código (autoestudo) |
| [`scripts/00_setup.sh`](scripts/00_setup.sh) | Habilita APIs, aplica IAM, cria bucket e dataset via gcloud |
| [`scripts/10_register_model.sh`](scripts/10_register_model.sh) | Registra o modelo no Model Registry via gcloud |
| [`scripts/20_deploy_endpoint.sh`](scripts/20_deploy_endpoint.sh) | Cria o endpoint e implanta o modelo via gcloud |
| [`scripts/30_teardown.sh`](scripts/30_teardown.sh) | **Encerra tudo na ordem correta** (undeploy → endpoint → modelo → artefatos) |

## 8. Ordem de leitura sugerida

1. Este `README.md` (visão geral e consumo de créditos).
2. [`00-pre-requisitos-e-gold.md`](00-pre-requisitos-e-gold.md) — **antes** da aula, para confirmar a gold.
3. [`01-setup-gcp.md`](01-setup-gcp.md) — ambiente pronto.
4. [`02-treino-e-experiments.md`](02-treino-e-experiments.md) → [`03-model-registry.md`](03-model-registry.md) → [`04-deploy-endpoint.md`](04-deploy-endpoint.md) — o fluxo da aula.
5. [`05-encerramento-custos.md`](05-encerramento-custos.md) — **obrigatório** ao final.

Docentes: comecem pelo [`roteiro-condutor.md`](roteiro-condutor.md).
