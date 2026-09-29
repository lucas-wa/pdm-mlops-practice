# Planejamento de duas aulas: MLOps na GCP

**Projeto integrador:** estimativa do preço anunciado de imóveis a partir dos dados da camada gold.

**Formato:** dois encontros, conduzidos por dois docentes. **Dia 1: no máximo 90 minutos no total, sendo 45 minutos de apresentação e demonstração e 45 minutos de prática guiada.** Dia 2: referência provisória de 180 minutos, sem intervalo contabilizado; duração ainda a confirmar.

**Divisão proposta:** Docente A conduz a primeira metade de cada encontro; Docente B conduz a segunda. Durante a prática, quem não estiver conduzindo acompanha os grupos e resolve dúvidas. Os nomes podem ser substituídos após a distribuição entre os professores.

## 1. Continuidade com as aulas anteriores

O material anterior trabalha anúncios de imóveis: ingestão pelo Pub/Sub, armazenamento no BigQuery e no Cloud Storage e extração de características de imagens com Gemini. As novas aulas começam na gold já preparada pela turma; a coleta e as transformações Bronze/Silver não precisam ser refeitas.

Os notebooks de referência não fixam o esquema final da gold. Antes das aulas, confirmar a tabela, as colunas disponíveis e a granularidade. As tabelas de anúncios e de características de imagens têm granularidades diferentes; a junção não pode multiplicar imóveis inadvertidamente.

| Item | Definição para a atividade |
|---|---|
| Pergunta | Quanto seria o preço anunciado de um imóvel com determinadas características? |
| Alvo | `preco`; representa preço de anúncio, não preço efetivo de venda |
| Entradas candidatas | `area_util`, `area_total`, `quartos`, `banheiros`, `garagens`, `bairro` e `cidade`, conforme disponibilidade na gold |
| Recorte | Imóveis à venda; preferencialmente uma cidade e um segmento com quantidade suficiente de exemplos |
| Modelo inicial | Random Forest pequena, em scikit-learn |
| Baseline | Previsão constante igual à mediana do preço do treino |
| Avaliação | MAE em reais; validação para seleção e conjunto de teste separado para avaliação final |
| Inferência | API HTTP que recebe características e devolve preço estimado e versão do modelo |

Conferir duplicatas por imóvel antes da separação dos dados. Se houver múltiplas observações do mesmo imóvel, mantê-las no mesmo conjunto. Excluir variáveis que entregam a resposta, como preço formatado e preço por metro quadrado calculado a partir do alvo. Ajustar imputação e codificação apenas no treino e salvar essas transformações junto com o modelo.

## 2. Resultados esperados

**Dia 1:** cada grupo executa um notebook preparado para treinar um modelo simples, verifica seu MAE e publica o artefato usando uma API pronta no Cloud Run. Experiments e Model Registry aparecem em uma demonstração breve, sem configuração pelos alunos.

**Dia 2:** cada grupo executa um pipeline que prepara dados, treina, avalia, registra resultados e publica uma versão aprovada. O fluxo deve preservar o serviço atual se o candidato for reprovado.

O segundo encontro terá **uma trilha prática escolhida previamente**. As três possibilidades abaixo são alternativas de arquitetura, não três atividades a executar na mesma aula.

## 3. Dia 1 — Da camada gold ao primeiro deploy

### Parte 1 — Conceitos essenciais e demonstração | Docente A | 45 minutos

| Horário relativo | Etapa | Condução e resultado esperado |
|---|---|---|
| 00–10 min | Retomar o problema | Mostrar a gold, as entradas e o preço a prever; apresentar o caminho até a API |
| 10–20 min | Explicar treino e avaliação | Apresentar separação dos dados, baseline e interpretação do MAE com um exemplo |
| 20–30 min | Introduzir MLOps | Explicar por que guardar dados, código, métricas e modelo; mostrar uma execução e uma versão já prontas no Vertex AI |
| 30–40 min | Demonstrar o resultado | Mostrar uma chamada à API e explicar o papel de Storage e Cloud Run |
| 40–45 min | Orientar a prática | Apresentar as células a executar e confirmar o acesso ao ambiente já preparado |

O Docente A entrega ao Docente B a definição do problema, as colunas aprovadas e a regra de avaliação. O Docente B usa o final desse bloco para identificar grupos com problemas de ambiente.

### Parte 2 — Treino e deploy guiados | Docente B | 45 minutos

| Horário relativo | Etapa | Ação dos alunos | Evidência |
|---|---|---|---|
| 45–50 min | Ler a gold | Executar consulta pronta sobre recorte pequeno e validado | Dataset carregado |
| 50–60 min | Treinar e avaliar | Executar treino preparado e observar MAE do modelo e do baseline | Modelo e métricas no notebook |
| 60–65 min | Salvar o modelo | Executar célula pronta que salva pré-processamento e modelo no Storage | URI exclusiva do artefato |
| 65–80 min | Fazer deploy | Executar comando preparado para criar revisão no Cloud Run com imagem da API já construída e URI do modelo | Revisão usando o modelo treinado |
| 80–85 min | Testar | Enviar JSON de exemplo e conferir preço previsto e identificação do modelo | Predição HTTP |
| 85–90 min | Fechar e absorver atrasos | Conferir entregas e apontar o que será automatizado no dia 2 | Resultado registrado pelo grupo |

**Para caber em 45 minutos de prática:** entregar notebook completo, consulta validada, dependências instaladas, permissões configuradas e imagem da API já construída no Artifact Registry. Usar poucas features e um modelo pequeno, com treino ensaiado para terminar em poucos minutos. A atividade é executar, interpretar e configurar o caminho do artefato; a escrita dos componentes fica para o dia 2.

O Cloud Run carregará o pipeline scikit-learn salvo no Storage. Neste primeiro deploy, a revisão aponta diretamente para uma URI exclusiva do modelo. O uso prático de Experiments, Model Registry, aprovação por métrica e publicação automatizada fica no dia 2.

**Contingência:** reservar os últimos cinco minutos para atrasos. Se o deploy de um grupo não concluir, demonstrar a chamada em serviço de referência, registrar o deploy como pendente e retomá-lo na abertura do dia 2. O serviço de referência não conta como deploy concluído pelo grupo.

**Entrega:** notebook executado, MAE observado, artefato no Storage e exemplo de chamada à API com o modelo treinado. A prática de experimentação e registro não é requisito de conclusão do dia 1.

## 4. Dia 2 — Escolha da arquitetura

| Possibilidade | Preparação dos dados | Treinamento | Orquestração | Inferência | Quando escolher |
|---|---|---|---|---|---|
| A — Vertex AI Pipelines | `BigqueryQueryJobOp` | Componente Python com scikit-learn | Vertex AI Pipelines | Modelo executado no Cloud Run | Recomendação para o conteúdo proposto |
| B — Airflow na GCP | `BigQueryInsertJobOperator` | Job de treinamento no Vertex AI | Airflow gerenciado, conhecido como Cloud Composer | Modelo executado no Cloud Run | Turma já conhece DAGs ou ambiente já existe |
| C — BigQuery ML | `BigqueryQueryJobOp` | `BigqueryCreateModelJobOp` | Vertex AI Pipelines | API Cloud Run chama endpoint Vertex AI | Turma domina SQL e deseja explorar treinamento no BigQuery |

Na alternativa A, há continuidade direta com o modelo e a API do dia 1. Na B, muda principalmente o orquestrador. Na C, mudam o mecanismo de treinamento e a forma de servir o modelo; ela demanda adaptação prévia dos materiais.

### Possibilidade A — Vertex AI Pipelines com componente BigQuery

**Objetivo:** transformar o notebook em componentes conectados e reutilizar SQL para produzir o dataset de treinamento. O BigQuery executa a consulta; o Vertex AI Pipelines coordena as etapas.

**Parte 1 — Docente A: dados, treinamento e rastreabilidade (90 minutos)**

| Tempo | Etapa | Implementação e saída |
|---|---|---|
| 0–15 min | Apresentar o fluxo | Relacionar etapas do notebook aos componentes; explicar parâmetros e artefatos |
| 15–35 min | Preparar os dados | `BigqueryQueryJobOp` materializa tabela identificada pela execução, com features, alvo e indicação do conjunto de dados |
| 35–50 min | Validar | Conferir colunas, quantidade mínima de exemplos, alvo válido e ausência de sobreposição entre conjuntos |
| 50–75 min | Treinar e avaliar | Componente Python lê a referência da tabela, treina e produz modelo e métricas; registrar resultados no Experiments |
| 75–90 min | Integrar e iniciar execução | Compilar/submeter o fluxo inicial; entregar URI do modelo, métricas e identificador da execução ao Docente B |

**Parte 2 — Docente B: API, aprovação e publicação (90 minutos)**

| Tempo | Etapa | Implementação e saída |
|---|---|---|
| 90–110 min | Construir a API | Completar esqueleto FastAPI: entrada tipada, carregamento na inicialização, `/health` e `/predict` |
| 110–130 min | Aprovar e registrar | Comparar MAE com baseline na mesma validação; registrar candidato e usar condição para permitir publicação |
| 130–155 min | Automatizar deploy | Componente próprio chama a API do Cloud Run, cria revisão sem tráfego geral e fixa URI imutável do modelo |
| 155–170 min | Validar serviço | Testar revisão candidata; promover tráfego se aprovada; consultar logs e versão retornada |
| 170–180 min | Demonstrar falha controlada | Mostrar execução reprovada e manutenção da versão atual; apresentar rollback para revisão anterior |

**Divisão técnica:** o Docente A prepara SQL, componentes de validação/treino e Experiments; o Docente B prepara API, registro, condição, atualização do Cloud Run e testes. A imagem base da API e o componente de deploy devem estar disponíveis antes do encontro.

**Entrega:** execução no Vertex AI Pipelines, referência dos dados, métricas rastreáveis, modelo registrado e API servindo a versão aprovada.

### Possibilidade B — Airflow/Cloud Composer com BigQuery operator

**Objetivo:** construir uma DAG de MLOps usando operadores de serviços GCP. O operador de BigQuery executa o SQL de preparação; o treinamento scikit-learn acontece em um job do Vertex AI, disparado pela DAG.

**Parte 1 — Docente A: DAG, dados e treinamento (90 minutos)**

| Tempo | Etapa | Implementação e saída |
|---|---|---|
| 0–15 min | Apresentar a DAG | Explicar tarefas, dependências, tentativas e parâmetros; usar ambiente previamente provisionado |
| 15–35 min | Preparar dados | `BigQueryInsertJobOperator` executa SQL e cria tabela por execução |
| 35–50 min | Validar a tabela | `BigQueryCheckOperator` verifica condições de qualidade e interrompe a DAG quando falham |
| 50–75 min | Disparar treinamento | Operador do provider Google submete job de treinamento no Vertex AI e acompanha conclusão |
| 75–90 min | Recuperar resultados | Ler métricas e URIs do job; conferir Experiments e entregar referências ao Docente B |

**Parte 2 — Docente B: decisão, deploy e operação (90 minutos)**

| Tempo | Etapa | Implementação e saída |
|---|---|---|
| 90–110 min | Construir a API | Completar o mesmo contrato FastAPI do dia 1 e validar carregamento do modelo |
| 110–130 min | Decidir e registrar | Tarefa de registro e ramificação por qualidade; candidato reprovado não segue para deploy |
| 130–155 min | Publicar revisão | Tarefa com SDK/API do Cloud Run atualiza o serviço com modelo e imagem identificados |
| 155–170 min | Testar e promover | Testar revisão sem tráfego geral, promover após sucesso e observar logs das tarefas |
| 170–180 min | Operar a DAG | Demonstrar reexecução, falha controlada e recuperação da revisão anterior |

**Divisão técnica:** o Docente A prepara ambiente Airflow, conexão GCP, SQL e job de treinamento; o Docente B prepara as tarefas de registro, decisão, deploy, teste e promoção. Fixar versões do Airflow e do provider Google compatíveis com os operadores escolhidos.

**Condições para caber na aula:** provisionar e autenticar o Airflow antes do encontro; disponibilizar o pacote ou imagem do treinamento. Entre tarefas, transmitir identificadores de tabela, job e objetos no Storage; os dados completos não devem circular pelo XCom.

**Entrega:** DAG executada, histórico de tarefas e tentativas, modelo registrado e serviço atualizado. Essa alternativa preserva Experiments e Model Registry; substitui o Vertex AI Pipelines como orquestrador.

### Possibilidade C — BigQuery ML com treinamento em SQL

**Objetivo:** mostrar uma arquitetura em que os dados e o treinamento permanecem no BigQuery. Para o exercício, usar regressão linear e uma separação explícita e reproduzível dos dados.

**Parte 1 — Docente A: preparação, treinamento e avaliação (90 minutos)**

| Tempo | Etapa | Implementação e saída |
|---|---|---|
| 0–15 min | Explicar a mudança | Contrastar execução scikit-learn com treinamento BigQuery ML; manter o problema e o recorte |
| 15–35 min | Preparar dados | `BigqueryQueryJobOp` materializa dados de treino, validação e teste |
| 35–55 min | Treinar | `BigqueryCreateModelJobOp` executa `CREATE MODEL` para uma regressão linear com nome por execução |
| 55–75 min | Avaliar | `BigqueryEvaluateModelJobOp` avalia a validação explícita; comparar MAE com baseline e registrar parâmetros/métricas no Experiments |
| 75–90 min | Registrar | Integrar o modelo ao Model Registry e entregar referência da versão e resultado da avaliação |

**Parte 2 — Docente B: serving gerenciado e API (90 minutos)**

| Tempo | Etapa | Implementação e saída |
|---|---|---|
| 90–110 min | Definir contrato | Completar a API FastAPI e adaptar payload de entrada para chamada ao endpoint Vertex AI |
| 110–140 min | Publicar modelo aprovado | Condição de qualidade libera deploy da versão em endpoint Vertex AI; acompanhar operação |
| 140–155 min | Publicar API | Cloud Run recebe requisição, autentica no Vertex AI e devolve a predição com identificação da versão |
| 155–170 min | Validar ponta a ponta | Testar entrada válida, inválida e falha do serviço de inferência; consultar logs |
| 170–180 min | Fechar | Relacionar modelo, endpoint e revisão da API; apresentar recuperação para versão anterior |

**Diferença de arquitetura:** nesta trilha, a API está no Cloud Run, mas a execução do modelo ocorre no endpoint Vertex AI. A integração de BigQuery ML com Model Registry permite disponibilizar modelos compatíveis sem exportação manual. Confirmar suporte do tipo de modelo e localização no ensaio do laboratório.

**Divisão técnica:** o Docente A prepara SQL, componentes BigQuery ML e registro dos experimentos; o Docente B prepara endpoint, permissões entre serviços e API intermediária. Provisionar um endpoint de referência antes da aula para demonstrar o resultado caso o deploy demore.

**Continuidade com o dia 1:** manter o primeiro encontro em scikit-learn para respeitar o limite de 90 minutos totais e 45 minutos de prática. Nesta trilha, explicar que o dia 2 implementa uma arquitetura alternativa, reutilizando o contrato de entrada, a gold e a avaliação. A configuração do endpoint Vertex AI fica no segundo encontro.

**Entrega:** pipeline com treinamento SQL, métricas registradas, versão no Registry, modelo disponível no Vertex AI e API no Cloud Run. Encerrar os recursos de serving após a atividade conforme o plano do laboratório.

## 5. Regras comuns às três possibilidades

1. **Rastrear os dados:** guardar tabela/snapshot ou extração por execução, filtro, colunas e regra de separação. Uma consulta com data de corte sobre tabela mutável, sozinha, não garante reprodução.
2. **Rastrear o modelo:** associar execução, parâmetros, métricas, versão do código, dependências e artefato. A integração com Experiments deve ser implementada; não presumir que qualquer execução aparecerá lá automaticamente.
3. **Definir qualidade antes do treino:** usar MAE menor que o baseline na validação como regra didática. Quando houver modelo vigente comparável, incluir comparação com ele. Reservar teste para avaliação final.
4. **Separar registro e promoção:** o candidato pode ser registrado mesmo se reprovado; a condição bloqueia a disponibilização. Preservar a versão ativa em caso de falha.
5. **Fixar versões no serving:** nas trilhas A/B, imagem e artefato imutáveis por revisão. Na C, identificar também a versão efetivamente implantada no endpoint; reverter só a API não reverte um endpoint alterado.
6. **Controlar publicação:** validar a nova versão antes de direcionar tráfego geral. A atualização do Cloud Run é uma etapa explícita do pipeline.
7. **Avaliar operação e qualidade separadamente:** disponibilidade, erros e latência verificam a API; MAE exige exemplos com valor observado. Logs operacionais não comprovam manutenção da qualidade preditiva.

## 6. Preparação e acordo entre os docentes

| Momento | Docente A | Docente B | Resultado compartilhado |
|---|---|---|---|
| Antes do dia 1 | Conferir gold, definir poucas features e baseline; entregar notebook pronto e demonstração de Experiments/Registry | Construir imagem da API, preparar Storage e comando de deploy; validar permissões | Prática ensaiada para caber em 45 minutos |
| Entre os encontros | Modularizar SQL, validação, treino e métricas | Modularizar API, registro, aprovação e publicação | Escolher uma trilha e fixar versões das dependências |
| Antes do dia 2 | Testar fluxo inicial e artefatos de saída | Testar consumo desses artefatos, publicação e recuperação | Uma execução aprovada e uma reprovada disponíveis |
| Durante a prática | Conduzir primeira parte; apoiar grupos na segunda | Apoiar grupos na primeira; conduzir segunda parte | Passagem de responsabilidade sem mudar contratos |
| Encerramento | Conferir resultados de treino e rastreabilidade | Conferir API e recursos de serving | Evidências entregues e recursos encerrados conforme combinado |

**Contrato de passagem:** projeto e localização, referência dos dados, nomes/tipos das features, referência do modelo, caminho das métricas, identificador da execução e formato JSON da API. Combinar esses campos antes de dividir a implementação.

**Ambiente:** validar faturamento, APIs, quotas e contas de serviço; acesso à gold, escrita de artefatos, execução de treinamento, registro e deploy. Respeitar a localização do dataset BigQuery e a compatibilidade regional dos demais recursos. Separar credenciais do notebook, do pipeline, do build e do serviço quando aplicável; a API deve ser testada com autenticação apropriada.

**Materiais:** notebook completo e imagem pronta da API para o dia 1; template da trilha escolhida, SQL de preparação e esqueleto da API para o dia 2; dependências fixadas, exemplos JSON e instruções de execução e encerramento. Manter um modelo, um serviço e uma execução de referência para contingência.

## 7. Ajustes de tempo e critérios de conclusão

O dia 1 tem limite de 90 minutos: não acrescentar escrita de API, configuração de infraestrutura, comparação de múltiplos candidatos ou montagem de pipeline. Se houver atrasos, encurtar a discussão e preservar treino, deploy e chamada à API. No dia 2, se a carga horária mudar, ajustar o volume de código a completar e usar execuções preparadas para demonstrar rollback. Comparação de atributos das imagens, agendamento e gatilhos são extensões para tempo adicional.

No dia 2, iniciar a execução assim que o primeiro fluxo estiver disponível e explicar a API enquanto as tarefas executam. Os tempos de provisionamento e deploy variam; não condicionar o fechamento a uma segunda execução completa ao vivo.

**Critérios do dia 1:** dados e alvo identificados; modelo treinado; MAE comparado ao baseline; artefato salvo; predição HTTP funcionando com o modelo do grupo. Identificar explicitamente qualquer deploy pendente.

**Critérios do dia 2:** pipeline executável; dados rastreáveis; aprovação por métrica; publicação identificada; evidência de que uma reprovação mantém o serviço atual. Agendamento, CI/CD por commit e monitoramento de distribuição ficam como expansão, salvo tempo adicional.

## 8. Referências

- [Aula anterior: Pub/Sub, BigQuery e Cloud Storage](https://github.com/robertogyn19/aula-pdm-pubsub/blob/main/gcp-pubsub-v2.ipynb).
- [Aula anterior: pipeline de anúncios e imagens](https://github.com/robertogyn19/aula-pdm-pubsub/blob/main/gcp-pipeline-anuncios.ipynb).
- [Vertex AI Experiments](https://docs.cloud.google.com/vertex-ai/docs/experiments/intro-vertex-ai-experiments): execuções, parâmetros, métricas e artefatos.
- [Vertex AI Model Registry](https://docs.cloud.google.com/vertex-ai/docs/model-registry/introduction): organização e versionamento de modelos.
- [Vertex AI Pipelines](https://docs.cloud.google.com/vertex-ai/docs/pipelines/introduction): componentes e orquestração de workflows de ML.
- [Componentes BigQuery e BigQuery ML](https://google-cloud-pipeline-components.readthedocs.io/en/google-cloud-pipeline-components-2.21.0/api/v1/bigquery.html): referência de versão dos componentes citados; fixar uma versão compatível no laboratório.
- [Operadores BigQuery no Airflow](https://airflow.apache.org/docs/apache-airflow-providers-google/stable/operators/cloud/bigquery.html): execução de consultas e validação de dados.
- [Airflow gerenciado na GCP / Cloud Composer](https://docs.cloud.google.com/composer/docs): orquestração de DAGs.
- [BigQuery ML e Model Registry](https://docs.cloud.google.com/bigquery/docs/managing-models-vertex): registro e disponibilização de modelos compatíveis.
- [Regressão linear no BigQuery ML](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/bigqueryml-syntax-create-glm): opções de treinamento SQL.
- [Modelos no Cloud Run](https://docs.cloud.google.com/run/docs/ai/use-cases): inferência e integração com Vertex AI.
- [Deploy a partir do código](https://docs.cloud.google.com/run/docs/deploying-source-code): Cloud Build e Artifact Registry.
- [Revisões, tráfego e rollback no Cloud Run](https://docs.cloud.google.com/run/docs/rollouts-rollbacks-traffic-migration).
