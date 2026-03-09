# Rastreamento Visual em Tempo Real em SoC FPGA

## Problema

Sistemas de robótica, vigilância e automação frequentemente precisam rastrear objetos em tempo real a partir de imagens. Entretanto, plataformas embarcadas possuem limitações de processamento, energia e latência, o que dificulta executar algoritmos de visão computacional complexos apenas em CPU ou GPU.

Assim, surge o desafio de desenvolver um **sistema de rastreamento visual eficiente que opere em tempo real em hardware embarcado**.

---

## Solução

Este projeto implementa um sistema de rastreamento visual utilizando uma abordagem de **coprojeto hardware/software em SoC FPGA**.

A extração de características visuais é acelerada em hardware por meio de um descritor **Histogram of Oriented Gradients (HOG)** implementado em FPGA. O rastreamento é formulado como um **problema de otimização bidimensional**, resolvido por algoritmos bioinspirados executados no processador ARM.

A comunicação entre hardware e software é realizada utilizando **AXI-Stream e DMA**, permitindo processamento eficiente em tempo real.

---

## Plataforma

- **Kria KV260 Vision AI Starter Kit**
- **Zynq UltraScale+ MPSoC**

---

## Ferramentas Utilizadas

### Hardware Design
- VHDL
- Vivado

### Sistemas Embarcados
- PYNQ
- Linux embarcado

### Software
- Python
- JupyterLab

### Protocolos e Integração
- AXI4
- AXI-Stream
- AXI-DMA

### Algoritmos
- HOG (Histogram of Oriented Gradients)
- PSO (Particle Swarm Optimization)
- GWO (Grey Wolf Optimizer)
- Firefly Algorithm

---

## Resultados

Melhor configuração testada:

ROI: **64 × 64 pixels**

| Algoritmo | FPS | IoU | CLE |
|-----------|-----|-----|-----|
| PSO | 16.30 | 0.8817 | 3.31 px |
| GWO | 17.99 | 0.8732 | 3.47 px |

Os resultados demonstram a **viabilidade de rastreamento visual em tempo real utilizando aceleração em FPGA**, desde que o sistema não exija taxa de atualização superior à obtida experimentalmente.

---
## Propostas de Melhorias
Algumas melhorias podem ser exploradas para elevar o desempenho, reduzir a latência e ampliar a aplicabilidade do sistema:

**Aumento da frequência de operação da FPGA**  
Uma evolução natural da arquitetura consiste em elevar a frequência de operação do acelerador de **50 MHz para 100 MHz**, desde que o fechamento de temporização seja atendido. 

**Maior paralelização do pipeline HOG**  
A arquitetura pode ser expandida para explorar ainda mais o paralelismo da FPGA, dividindo o cálculo do descritor HOG em mais estágios ou replicando partes do pipeline. Essa abordagem pode aumentar o throughput e reduzir o tempo total de extração de características.

**Implementação bare-metal no PS**  
A substituição do ambiente atual por uma implementação **bare-metal em C/C++** no processador pode reduzir overheads do sistema operacional e melhorar a previsibilidade temporal da solução embarcada.

**Critérios de parada adaptativos nos algoritmos bioinspirados**  
Os algoritmos de otimização podem ser aprimorados com critérios adicionais de parada, como:
- limiar mínimo de custo
- detecção de estagnação
- interrupção antecipada por convergência
- parada baseada em estabilidade da solução entre iterações

Esses mecanismos podem reduzir o tempo médio de execução sem comprometer a qualidade do rastreamento.

**Melhor exploração da vetorização no software**  
Outra possibilidade é otimizar o software embarcado com técnicas adicionais de vetorização e organização de memória, reduzindo o custo computacional das etapas executadas no processador.

**Redução do custo computacional da função de avaliação**  
Uma direção promissora consiste em substituir ou complementar a função de custo atual por métricas menos exigentes computacionalmente e mais aderentes ao problema de rastreamento. Entre as possibilidades, podem ser investigadas:


## Autor

Nathan Spínola Zeidan  
Engenharia Eletrônica — Universidade de Brasília
