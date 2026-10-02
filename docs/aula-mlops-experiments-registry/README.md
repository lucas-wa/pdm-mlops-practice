# Introdução ao MLOps no GCP: Experiments + Model Registry no Vertex AI

Tutorial de ~1 hora, ao vivo pelo console do Google Cloud: da camada **gold** do BigQuery (dataset `aula_pdm`, `us-central1`) a um modelo treinado, rastreado, versionado e servido em endpoint de predição online.

> **AVISO DE CONSUMO DE CRÉDITOS — LEIA ANTES DE COMEÇAR**
>
> A turma usa **créditos educacionais do Google Cloud**: **não há cobrança no cartão de ninguém**. Os créditos, porém, são **finitos**.
>
> Esta aula cria recursos que **consomem créditos por hora enquanto existirem**, mesmo sem tráfego. O maior consumidor é o **Endpoint com modelo implantado** (`rf-preco-imoveis-endpoint`): os nós ficam ligados 24/7 até o *undeploy* e a deleção do endpoint.
>
> **Ao terminar, execute o checklist de encerramento:** [`05-encerramento-custos.md`](05-encerramento-custos.md). É higiene de ambiente — mantém o saldo disponível para as próximas atividades. Ele é feito **ao vivo, junto com a turma**, nos últimos minutos da aula. Não deixe para depois.

---

## 1. O que é MLOps, em três frases

**Vertex AI Experiments** guarda o histórico de cada treino — parâmetros, métricas e artefatos. **Vertex AI Model Registry** guarda o modelo como objeto versionado, com identidade e alias. **Vertex AI Endpoint** publica uma versão registrada atrás de uma API HTTP.

MLOps liga as três: **rastrear**, **versionar** e **publicar**, de forma que outra pessoa consiga reproduzir, auditar e reverter.

## 2. Objetivos de aprendizagem

1. Ler a gold do BigQuery e montar treino/validação/teste respeitando o contrato de dados.
2. Treinar um pipeline scikit-learn (`RandomForestRegressor`) para prever `preco` e comparar o **MAE** com o **baseline da mediana**.
3. Registrar **duas execuções** no experimento `preco-imoveis-rf` e compará-las no console.
4. Registrar o modelo como `rf-preco-imoveis`, criar uma **nova versão** e entender o alias `default`.
5. Implantar a versão em `rf-preco-imoveis-endpoint` e obter uma **predição online** na ordem canônica de features.
6. Executar o **checklist de encerramento** e explicar qual recurso consome quanto crédito.

## 3. Pré-requisitos

| Item | Detalhe |
|---|---|
| Projeto GCP | Projeto próprio com **faturamento ativo**, vinculado aos **créditos educacionais** da disciplina. |
| Acessos | Cada aluno é **`Owner` do próprio projeto** — `roles/owner` já cobre tudo e **não é preciso conceder nenhum papel**. Os papéis mínimos em [`01-setup-gcp.md`](01-setup-gcp.md) são referência para projeto compartilhado. |
| Região | Todos os recursos em **`us-central1`**, para casar com o dataset do BigQuery. |
| Camada gold | Tabela gold no dataset `aula_pdm`, com nome e schema **confirmados antes da aula**. |
| Ambiente | **BigQuery Studio** (runtime Colab Enterprise) — nada a instalar na máquina local. Importar o notebook e conectar o runtime: Passo 6 de [`01-setup-gcp.md`](01-setup-gcp.md). |
| Conhecimento | Python básico, pandas e noções de treino/validação/teste. |

Contrato de dados e detalhamento em [`00-pre-requisitos-e-gold.md`](00-pre-requisitos-e-gold.md). Leia antes da aula.

## 4. Como esta aula é conduzida

- **Ao vivo, pelo console** (Vertex AI → Experiments, Model Registry, Online prediction) e pelo notebook no BigQuery Studio. Os arquivos `00`–`05` na raiz são esse caminho.
- **gcloud e Terraform são autoestudo.** [`gcloud/`](gcloud/README.md) e [`terraform/`](terraform/README.md) reproduzem o mesmo resultado por CLI e IaC — **não** serão executados durante o encontro.
- **Nem tudo tem equivalente em IaC.** Experiments, registro de modelo e deploy em endpoint ficam em SDK, gcloud ou console. Detalhes em [`terraform/README.md`](terraform/README.md).

> **Nomes no console.** A documentação do Google já aparece como **"Gemini Enterprise Agent Platform"**, mas o **console ainda exibe "Vertex AI"** — os rótulos aqui seguem o console.

## 5. Convenções de nomes

Usados **exatamente assim** em todos os arquivos, notebooks e scripts da aula.

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

> **Atenção ao bucket.** `${PROJECT_ID}-mlops-aula` é criado **para esta aula** e pode ser esvaziado no encerramento. `${PROJECT_ID}-aula-pdm` é infraestrutura **compartilhada** e **não deve ser apagada**.

## 6. Agenda (~1 hora)

| Tempo | Bloco | Resultado esperado |
|---|---|---|
| 00–05 | Contexto e objetivos | Turma entende o caminho gold → modelo rastreado → versionado → servido |
| 05–20 | Treino + Experiments | Modelo treinado, MAE comparado ao baseline, 2 runs comparadas no console |
| 20–30 | Model Registry | `model.joblib` no GCS, modelo `rf-preco-imoveis` registrado, nova versão + alias |
| 30–45 | Deploy em Endpoint | Endpoint respondendo `/predict` (deploy **iniciado cedo**, em paralelo) |
| 45–55 | Encerramento e consumo de créditos | Teardown executado ao vivo; budget configurado |
| 55–60 | Fechamento | Entregas conferidas e ponte para o Dia 2 (orquestração/pipelines) |

Com o deploy, a aula pode esticar para **75–90 minutos**. O caminho **sem deploy** (treino → Experiments → Registry) é o *fallback* quando o tempo apertar. Contingências no [`roteiro-condutor.md`](roteiro-condutor.md).

## 7. Estrutura do material

```
aula-mlops-experiments-registry/
  README.md  roteiro-condutor.md
  00-pre-requisitos-e-gold.md
  01-setup-gcp.md              <- caminho CONSOLE (o da aula)
  02-treino-e-experiments.md
  03-model-registry.md
  04-deploy-endpoint.md
  05-encerramento-custos.md
  notebooks/treino_experiments_registry.ipynb
  gcloud/      <- os mesmos passos por linha de comando (autoestudo)
  terraform/   <- APIs, bucket e dataset como código (autoestudo)
```

### Caminho da aula (console) — raiz

| Arquivo | Conteúdo |
|---|---|
| [`00-pre-requisitos-e-gold.md`](00-pre-requisitos-e-gold.md) | Pré-requisitos, contrato de dados, anti-vazamento, dedup, baseline e schema da gold |
| [`01-setup-gcp.md`](01-setup-gcp.md) | APIs, IAM, bucket e dataset pelo console; abrir o notebook no BigQuery Studio |
| [`02-treino-e-experiments.md`](02-treino-e-experiments.md) | Leitura da gold, treino do RandomForest, baseline, MAE e runs no Experiments |
| [`03-model-registry.md`](03-model-registry.md) | Salvar `model.joblib` no GCS, registrar `rf-preco-imoveis`, versões e aliases |
| [`04-deploy-endpoint.md`](04-deploy-endpoint.md) | Criar `rf-preco-imoveis-endpoint`, implantar o modelo e predizer online |
| [`05-encerramento-custos.md`](05-encerramento-custos.md) | **Checklist de teardown**, budgets e alertas, créditos educacionais |
| [`roteiro-condutor.md`](roteiro-condutor.md) | Roteiro minuto a minuto para o docente |
| [`notebooks/treino_experiments_registry.ipynb`](notebooks/treino_experiments_registry.ipynb) | Notebook executável de ponta a ponta no BigQuery Studio |

### Caminhos alternativos (autoestudo)

| Caminho | Conteúdo |
|---|---|
| [`gcloud/README.md`](gcloud/README.md) | A aula inteira por linha de comando, numerada 0 a 5 |
| [`gcloud/seed_gold.sh`](gcloud/seed_gold.sh) | Valida a camada gold e a reconstrói se estiver faltando ou mal formatada |
| [`gcloud/00_setup.sh`](gcloud/00_setup.sh) | Habilita APIs, aplica IAM, cria bucket e dataset |
| [`gcloud/10_register_model.sh`](gcloud/10_register_model.sh) | Registra o modelo no Model Registry |
| [`gcloud/20_deploy_endpoint.sh`](gcloud/20_deploy_endpoint.sh) | Cria o endpoint e implanta o modelo |
| [`gcloud/30_teardown.sh`](gcloud/30_teardown.sh) | **Encerra tudo na ordem correta** (undeploy → endpoint → modelo → artefatos) |
| [`terraform/README.md`](terraform/README.md) | Provisionamento declarativo e **o que o Terraform NÃO faz** |

## 8. Ordem de leitura sugerida

1. Este `README.md` (visão geral e consumo de créditos).
2. [`00-pre-requisitos-e-gold.md`](00-pre-requisitos-e-gold.md) — **antes** da aula, para confirmar a gold.
3. [`01-setup-gcp.md`](01-setup-gcp.md) — ambiente pronto.
4. [`02-treino-e-experiments.md`](02-treino-e-experiments.md) → [`03-model-registry.md`](03-model-registry.md) → [`04-deploy-endpoint.md`](04-deploy-endpoint.md) — o fluxo da aula.
5. [`05-encerramento-custos.md`](05-encerramento-custos.md) — **obrigatório** ao final.

Docentes: comecem pelo [`roteiro-condutor.md`](roteiro-condutor.md).
