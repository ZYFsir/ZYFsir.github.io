---
title: Agent必学：agent架构的演变历程
description: 介绍接下来以"Agent技术"为核心的写作计划
date: 2026-04-10
lastmod: 2026-04-23
weight: 2
categories:
  - Agent
tags:
  - 日常
---


Agent 系统架构演变完整调研

## 一、总览：三代范式跃迁

Agent 系统架构的演变可归纳为三条并行的技术主线，历经约 70 年的迭代。按照核心驱动力，可划分为**符号主义时代 → 强化学习时代 → LLM 原生时代**三大范式。当前正处于第三次范式的高潮期，且呈现出**多范式融合**的趋势。

---

## 二、第一阶段：符号主义 / 经典 Agent 架构（1950s–1990s）

Agent理论的发展比深度学习还要早。
在ChatGPT这种能够真正回答人类问题的AI出现之前，就已经开始思考“一个完全由人工定义的智能会是什么样子”这一问题。
这点来讲，哲学理论走得要远远超前。

### 2.1 规则系统（Rule-Based Systems）

最早的 AI Agent 以 **专家系统（Expert Systems）** 为代表。架构核心是：

```
知识库（Knowledge Base） + 推理引擎（Inference Engine）
```

- 知识以 **if-then 规则** 显式编码
- 推理引擎执行前向/后向链式推理
- 典型代表：MYCIN（1976，医疗诊断）、DENDRAL（1965，化学分析）

**局限**：规则数量爆炸、无法处理模糊/未知场景、完全不具备学习能力。

我甚至不认为规则系统该作为Agent理论的一部分，它用众多规则堆砌出决策，似乎跟智能毫无关系。

但是目前的智能体有个说法：与其要求ai按照严格语法编写代码，不如让它编写完后执行一遍检查。规则系统适合ai与严谨的外部环境交互时使用。

### 2.2 BDI 架构（Belief-Desire-Intention）

这个理论是来自哲学界的产物，研究的是人类的行为。

早期的哲学中认为欲望驱动理性。Hume 的核心论证极其著名，就一句话：

| "Reason is, and ought only to be the slave of the passions."
|（理性是，也只应当是激情的奴隶。——《人性论》2.3.3）

这一观点不依赖任何实验，仅仅通过内省和推理便收获了人们的认可。

转换到Agent理论中，可以想象，如果让当时的人们设计一个智能体，他们设想的架构会是：给agent设定一个目标(Desire)，agent用它的知识(Belief，指ai相信的世界知识)完成目标。

即使放到今天，这个想法也不能说是错，但它很粗糙，表达起来很主观，比如Desire跟Belief是什么，都没有明确的定义。只是一种感觉上的描述。

Dennett(1971)将它更具体一些，让这个理论更像是科学里的描述了： 当我们说一个人有 belief 和 desire，不是说我们真的在他的大脑里找到了这些实体——而是说，用这组概念来预测他的行为，是最有效的策略。

当理解物理系统时，我们依靠精确但复杂的物理规律去了解；当理解人造物时，我们可以从它的设计目的去了解；当想要了解人类、动物、AI时，我们用belief和desire理论去了解。

当我们想要科学地研究agent(或人)时，我们
1. 假设agent是理性的
2. 根据它的处境和目的，赋予它应有的belief和desire
3. 预测理性系统会作出的最符合这些belief和desire的事

从此时开始，Belief-Desire理论听上去很像是严谨的科学了。它像是在强调，心理学其实是一种概率学，一种工具；也可以反过来理解，借助生成最高概率的做法，就能模拟出一个理性系统。

Michael Bratman（1987）的哲学理论，则认为Belief-Desire理论在解释瞬时行动的时候是合理的，但对于跨时间的计划行为，它的解释力不足。
1. 想要的未必真的就去做。例如用户可能希望去巴黎旅行，但这并不意味着会立刻触发“订机票、办签证、订住宿”这一系列流程。Desire List不会立刻触发行动。
2. 想要的东西之间存在矛盾。例如用户想吃蛋糕，以及希望减肥。如果Desire List以同等的地位进入执行阶段，便发生了冲突。但它们在Desire阶段是完全能够共存的。这也说明Desire到执行这一步之间，还存在一些步骤。

他引入了Intention(意图)，即决定要去做的事。Desire经过“作出承诺要做这件事”这一步骤后，才进入到执行阶段。

这一理念将 Agent 建模为三种心理状态：

| 组件 | 含义 | 类比 |
|------|------|------|
| **Belief（信念）** | 对环境状态的认知 | 数据库/知识图谱 |
| **Desire（愿望）** | 目标状态/偏好 | 目标队列 |
| **Intention（意图）** | 已承诺执行的计划 | 执行栈 |

仅仅有Desire不代表真正去做，Intention，也就是下决心真的要去做的时候，才真正开始做。执行阶段不属于心理状态，因此不在表中。

Intention这一阶段的引入提供了三种作用：
1. 用Intention作为推理与执行的起点，而不是以Desire作为起点。同时想要减肥与吃蛋糕，欲望是同时存在的，但下决心，到了真正要指导行动的时候，只会留下一个Intention。
2. Intention可以实现跨时间协调，也就是对人的“惯性心理”的刻画。人并不会时时刻刻对所有Desire进行评估并重新规划。而是延续之前的“决定”，完成之前心中的承诺。例如在已经决定减肥后，默认的Intention依然是减肥，而不是再次比较一番所有Desire，完全独立的重新构建新的Intention。它不是不可改变，但它会抵抗改变，人们借此得以执行跨越时间的计划。
3. 在公共关系中同样需要“决定”这一步骤。“我想帮你”与“我会帮你”是存在不同的，在多agent系统中，就可能有必要区分清楚。

**代表性框架**：AgentSpeak(L)、Jason、PRS（Procedural Reasoning System）。BDI 至今仍在 MAS（Multi-Agent Systems）研究中有影响力——它将"计划选择"和"目标承诺"显式分离，是 Agent 架构中"认知层"概念的原型。

这些理论都是基于自省、思维实验构建的。跟工科认知中的科学相差甚远。这种理论通常需要依赖反证法：当缺失这一概念时，理论会怎样的不完善。从而使新理论得到认可。

### 2.3 SOAR 认知架构（1987）

SOAR（State, Operator And Result ）是Allen Newell、John Laird 等人提出的**通用认知架构**，目标是实现通用人工智能。

这是一个宏大的命题：
既然人类能在所有认知领域表现出智能，那么一定存在一套固定的、通用的底层机制——这个机制就是认知架构（cognitive architecture）。SOAR 是这一机制的一种实现。

SOAR 不是"一个 AI 程序"，而是一套关于智能是什么的理论——它说：任何表现出通用智能的系统，都得有某种固定的结构，这个结构包含什么记忆系统、什么决策流程、什么学习机制。

核心机制：

```
短期记忆（STM） ↔ 决策周期 ↔ 长期记忆（生产规则 + 语义 + 情节）
            ↕
      意向栈（Goal Stack）
```

- **决策周期（Decision Cycle）**：感知 → 匹配规则 → 冲突消解 → 执行 → 学习（Chunking）
- **通用子目标（Universal Subgoaling）**：遇到困境自动创建子目标
- **学习机制 Chunking**：将解决方案编译为新的规则

SOAR 在 AI Agent 架构史上有着里程碑地位——它首次完整定义了 **感知 - 推理 - 执行 - 学习**的闭环架构，影响了后续几乎所有 Agent 架构的设计。

要我说，ReAct循环完全跟这个一样，所以算不上什么新东西。只不过SOAR提出的时间太久远了，人们又只关注近期的知识。这恐怕是人类在知识继承里的常态。

| 任何需要“在环境中持续行动的智能系统”，都需要有类似这样的闭环，这不能说是发明，而是一种工程约束。

顺便一提，SOAR可以称得上是早期的“终身学习系统”了，跟现在agent常见的宣传一样，都号称越用越聪明。

1. 外部输入
2. 思考
	1. 根据外部输入匹配规则
	2. 消解冲突规则，选择其中的规则
3. 执行
	1. 成功则输出
	2. 不成功则拆解任务为子目标
		1. 重复循环直到问题解决
		2. Chunking 将解决问题的方案编译为规则，下次遇到同样问题能够快速处理。

这其中的Chunking能力就跟Hermes Agent完成任务后编写SKILL的做法一样，并因此号称终身学习。

SOAR的认知架构（对应Agent记忆系统）同样是类似如今的多层架构，一共有9个记忆系统
1. 工作记忆。这是SOAR管理全局的记忆，所有输入，中间推理，决策状态都在这里，并用栈结构分层表示目标与状态，子目标与子状态。相当于主Agent。

SOAR架构没有死，甚至还活跃着。
### 2.4 ACT-R 架构

Anderson 等人开发的认知架构，专注于模拟人类认知过程。相比 SOAR 的全符号主义，ACT-R 引入了**亚符号层（subsymbolic）**，包括：

- **扩散激活（Spreading Activation）**：记忆检索的基础
- **效用学习（Utility Learning）**：规则选择的最优化

ACT-R 是将"计算精度"与"认知真实性"结合的典范，后来被部分 LLM Agent 的记忆设计参考。

---

## 三、第二阶段：强化学习 Agent 架构（1990s–2010s）

### 3.1 经典 RL Agent（Q-Learning, SARSA）

RL 将 Agent 定义为 **MDP（马尔可夫决策过程）** 中的决策者：

```
状态(State) → 动作(Action) → 奖励(Reward) → 新状态(State')
```

架构特征：
- **Value-based**：Q-Learning，维护 Q(s,a) 表
- **Policy-based**：REINFORCE，直接学习策略 π(a|s)
- 局限：状态空间受限，难以应对高维感知

### 3.2 深度 RL Agent（DQN, 2013）

DeepMind 的 **DQN（Deep Q-Network）** 引发 RL 革命，关键架构创新：

```
CNN（视觉编码器）→ Q(s,a) Value Network → ε-greedy 策略
                              ↕
                    经验回放缓冲区（Experience Replay）
                              ↕
                    Target Network（稳定目标分布）
```

- **经验回放（Experience Replay）**：打破时序相关性
- **两阶段目标网络（Double DQN）**：减少价值过估计

### 3.3 Actor-Critic 架构（PPO, SAC）

现代 RL Agent 的主流架构。分离 **策略网络（Actor）** 与 **价值评估网络（Critic）**：

```
┌─────────────┐    ┌──────────────┐
│  Actor       │    │  Critic       │
│  π(a|s)      │←───│  V(s) / Q(s,a)│
│  生成动作     │    │  评估动作质量  │
└──────┬───────┘    └──────┬────────┘
       │                   │
       └─────────┬─────────┘
                 ▼
         环境交互 → 奖励信号
```

**PPO（Proximal Policy Optimization, 2017）** 使用 **Clip 机制**限制策略更新范围，成为 RL Agent 的事实标准。**SAC（Soft Actor-Critic）** 通过最大熵强化学习增强了探索能力。

RL Agent 的架构范式（感知 → 决策 → 执行 → 学习循环）为后来的 LLM Agent 提供了**循环结构**的设计母板。

### 3.4 多智能体 RL（MADDPG, 2017）

Lowe 等人提出 **MADDPG（Multi-Agent DDPG）**，架构核心：每个 Agent 的 Critic 可以观察所有 Agent 的动作（CTDE: Centralized Training, Decentralized Execution）。

```
Agent 1: Actor(s₁) → a₁ │ Critic(s₁, s₂, a₁, a₂) → Q₁
Agent 2: Actor(s₂) → a₂ │ Critic(s₂, s₁, a₂, a₁) → Q₂
```

这在多 Agent 协作/竞争的架构设计上提供了基础范式，后来被 LLM Agent 框架（AutoGen、CrewAI）在概念层借鉴。

---

## 四、Pre-LLM 混合架构与过渡期

### 4.1 RLL（Reinforcement Learning with Language）

在 LLM 大爆发前，研究者试图将**自然语言**引入 Agent 架构。典型代表：

- **Embodied Agents (ALFRED, 2020)**：通过指令->子任务分解->RL策略
- **Interactive Fiction Agents (Jericho, 2019)**：自然语言文本界面 + RL

### 4.2 基于 LSTM/Transformer 的命令理解 Agent

- **WebGPT（OpenAI, 2021）**：用 GPT-3 + 模仿学习操作浏览器，首次展示了"语言模型 + 工具 + 搜索"的 Agent 雏形
- 架构：Behavior Cloning on human demonstrations + RL fine-tuning

这些系统虽然性能有限，但建立了**语言模型作为 Agent 控制器**的架构原型，是通往 LLM Agent 的关键桥梁。

---

## 五、第三阶段：LLM Agent 革命（2023–至今）

### 5.1 分水岭事件：GPT-4 Function Calling（2023-06）

2023年6月，OpenAI 发布 GPT-4 的 function calling 能力。这是 Agent 架构史上的**分水岭**。

**架构变革**：

```
之前: User → LLM → Text Output → 手动解析 → 调用API
之后: User → LLM → JSON tool_call → 自动执行 → 结果反馈 → LLM
```

Function Calling 使得 LLM 可以：

1. **结构化输出函数参数**（不再是自由文本）
2. **多轮工具调用**（chain of tool calls）
3. **自动反馈循环**（工具结果作为上下文回注）

这标志着 **LLM-based Agent** 时代正式开启。

### 5.2 ReAct 范式的崛起（Yao et al., 2023）

ReAct（Reasoning + Acting）是 LLM Agent **最核心的架构范式**，由 Yao 等人在 2023 年提出。

```
Thought: 我需要查找当前的天气数据
Action: search_weather(location="Beijing")
Observation: {"temp": 28, "humidity": 65%}
Thought: 气温 28°C，湿度 65%，建议穿短袖
Action: complete
```

**架构循环**：

```
┌─────────────────────────────────────┐
│  LLM (核心推理引擎)                   │
│                                      │
│  思考(Thought) → 动作(Action)        │
│       ↑                  ↓           │
│  观察(Observation) ← 工具执行结果     │
│       ↑                              │
│  Scratchpad (上下文缓冲区)            │
└─────────────────────────────────────┘
```

ReAct 的关键设计要素：

- **Scratchpad**：作为 Agent 的"工作记忆"，存储推理链
- **Thought-Action-Observation 三元组**：可解释的决策轨迹
- **动态停止条件**：Agent 自行判断任务是否完成

### 5.3 第一代自主 Agent 框架（2023 年中）

**AutoGPT（2023-03）** 和 **BabyAGI（2023-04）** 引爆了 Agent 概念。

AutoGPT 架构：

```
┌─────────────────────────────────────────┐
│  Goal → 任务队列(Task Queue)             │
│           ↓                              │
│  LLM 推理 → 执行动作 → 存储结果          │
│           ↓                              │
│  优先队列(优先级排序 → 再次执行)         │
│           ↓                              │
│  向量数据库(长期记忆检索)                 │
└─────────────────────────────────────────┘
```

BabyAGI 架构创新：引入了**任务分解（task decomposition）** 与**记忆优先级（memory prioritization）**，但其无限制的自我循环也引发了"Agent 失控"的讨论。

### 5.4 主流框架生态成型（2023 年底–2024 年）

| 框架 | 发布时间 | 架构特色 | 核心理念 |
|------|---------|---------|---------|
| **LangChain** | 2023-01 | 链式组合（Chain）+ 工具抽象 | 可组合的 LLM 应用框架 |
| **LangGraph** | 2023-中 | 有向图状态机 + 循环节点 | 细粒度控制 Agent 流程 |
| **AutoGen** | 2023-10 | 多 Agent 对话 + 角色分离 | Agent 即消息参与者 |
| **CrewAI** | 2023-12 | 角色 + 任务 + 团队（Crew） | 模拟人类团队协作 |
| **Semantic Kernel** | 2023-05 | 编排层 + 插件 + 记忆 | 企业级 Agent 架构 |
| **LlamaIndex** | 2023-01 | 数据索引（Index）+ RAG | Agent 检索增强架构 |

#### LangChain → LangGraph 的架构进化

LangChain 最初使用 **Sequential Chain**（线性管道），架构为：

```
Input → PromptTemplate → LLM → OutputParser → NextChain → ...
```

问题：线性链条无法处理**条件分支、循环、多工具调用**。

**LangGraph** 的革命性升级：

```
StateGraph:
  Node(agent) → Edge(router) → Node(tools)
     ↑                             │
     └─────────────────────────────┘
     (循环，直到 agent 决定停止)
```

LangGraph 引入了：
- **Stateful Graph**：节点间通过共享状态通信
- **Conditional Edges**：根据条件动态路由
- **Persistence**：内置的持久化/中断/恢复机制

#### AutoGen 的对话式架构

Microsoft AutoGen 的架构核心是 **Agent-Centric** 的消息驱动模型：

```
┌─────────────────────────────────────────────┐
│  UserProxyAgent       AssistantAgent         │
│  (人类代理)             (LLM代理)             │
│       │                      │              │
│       └─────── 对话循环 ──────┘              │
│                  │                           │
│            Tool/Function                     │
│           (代码/API执行)                      │
└─────────────────────────────────────────────┘
```

关键创新：**多 Agent 通过自然语言对话完成协作**，而非硬编码的流程控制。

#### CrewAI 的角色化架构

CrewAI 引入了**组织隐喻（Organizational Metaphor）**：

```
Crew (团队)
├── Agent: 研究员（角色: 研究者, 目标: 收集信息, 工具: web_search）
├── Agent: 分析师（角色: 分析师, 目标: 分析数据, 工具: code_exec)
├── Task: 收集数据（分配给 研究员 Agent）
└── Task: 生成报告（分配给 分析师 Agent, 依赖 Task1）
```

设计理念：将 Agent 组织视为**虚拟公司**，通过角色、职责、任务的显式分配来解耦复杂系统。

### 5.5 Prompt Agent → 工具 Agent 的架构转变

2024 年的关键趋势是从**提示代理（Prompt Agent）** 向**工具代理（Tool Agent）** 的演变：

```
Prompt Agent:
  单一 LLM 调用 → 文本输出
  无外部反馈循环
  依赖模型能力

Tool Agent:
  LLM(工具描述 + 上下文) → tool_call → 执行结果 → LLM(结果)
  结构化工具接口
  持续交互闭环
```

**Function Calling / Tool Use** 成为 Agent 架构的标准层：

```
Agent
├── Orchestrator（编排器：决定调用哪个工具、何时停止）
├── Tool Registry（工具注册表：名称+描述+参数Schema）
│   ├── search | code | calculator | file_ops | ...
│   └── MCP Tool（通过 Model Context Protocol 发现）
├── Memory（记忆系统）
│   ├── Working Memory（Scratchpad）
│   ├── Short-term（对话历史）
│   └── Long-term（向量检索 + 持久化）
└── Safety Layer（安全层：输入过滤 + 输出审核）
```

---

## 六、多 Agent 系统架构成熟期（2024–2025）

### 6.1 主流多 Agent 架构模式

#### 模式 1：中心化编排器（Orchestrator）

```
┌──────────────┐
│ Orchestrator  │ ← 单一决策点
├──────┬───────┤
│      │       │
  ↓     ↓       ↓
Agent1 Agent2 Agent3
```

- 代表：LangGraph（Supervisor Pattern）
- 优点：全局可控、确定性高
- 局限：单点瓶颈、编排器可能成为性能瓶颈

#### 模式 2：对话式协作（Conversational）

```
Agent1 ←→ Agent2 ←→ Agent3
   ↕        ↕          ↕
  Tool     Tool       Tool
```

- 代表：AutoGen
- 优点：自然协作、灵活性高
- 局限：对话开销、可能陷入循环

#### 模式 3：分层管理（Hierarchical）

```
Manager Agent
├── Researcher Agent
│   ├── Web Searcher
│   └── Paper Analyzer
├── Writer Agent
└── Reviewer Agent
```

- 代表：Anthropic Multi-Agent Research System
- 优点：任务分解自然、各层职责清晰
- 局限：层级间通信延迟

#### 模式 4：群体智能（Swarm）

```
  Agent1 → Agent2 → Agent3
  ↑ Agent4 → Agent5 ↕
  Agent6 ← Agent7 ← Agent8
```

- 代表：OpenAI Swarm、MADDPG 精神延续
- 优点：容错、可扩展
- 局限：协调复杂、调试困难

### 6.2 关键研究成果

| 研究 | 年份 | 架构贡献 |
|------|------|---------|
| **ReAct** (Yao et al.) | 2023 | Thought-Action-Observation 循环 |
| **Reflexion** (Shinn et al.) | 2023 | 语言反馈 + 自我反思 + 经验回放 |
| **Tree-of-Thoughts** (Yao et al.) | 2023 | 多路径探索 + BFS/DFS |
| **Self-Refine** (Madaan et al.) | 2023 | Agent 自我生成 → 自我反馈 → 自我改进 |
| **ReWOO** (Xu et al.) | 2023 | 规划与执行分离（Plan-then-Execute） |
| **AgentTuning** (Zeng et al.) | 2023 | 从 Agent 轨迹中微调 LLM |
| **GPT-4 Function Calling** | 2023-06 | 原生工具调用接口 |
| **MCP (Model Context Protocol)** | 2024-11 | 标准化工具/数据协议 |
| **A2A (Agent-to-Agent)** | 2025-04 | Agent 间通信协议 |
| **Deep Research (OpenAI)** | 2025-02 | 多层搜索 + 规划 + 报告合成 |
| **Anthropic MCP** | 2024-11 | Function Calling 的协议级标准化 |

### 6.3 Reflexion 架构：Agent 的自我改进

Reflexion（Shinn et al., 2023）在 ReAct 基础上引入**评估-反思闭环**：

```
┌─────────────────────────────────────┐
│  Actor (ReAct Loop)                  │
│  Thought → Action → Observation     │
└─────────────┬───────────────────────┘
              │ 完成/失败
              ▼
┌─────────────────────────────────────┐
│  Evaluator                           │
│  评估任务完成质量 → 生成反馈          │
└─────────────┬───────────────────────┘
              │ 结构化反馈
              ▼
┌─────────────────────────────────────┐
│  Memory                             │
│  经验回放缓冲区（失败的决策 + 原因）  │
└─────────────┬───────────────────────┘
              │ 提取经验
              ▼
        回到 Actor 重新执行
```

核心创新：Agent 通过**自然语言反思自己的失败**并将经验存入记忆，而非通过权重更新。

---

## 七、协议标准化时代（2024 年底–2026）

### 7.1 MCP（Model Context Protocol）

Anthropic 于 2024 年 11 月推出的开放协议，定位在 **Agent 与工具/数据源之间**的标准化接口。2025 年 12 月，Anthropic 将其捐赠给 Linux 基金会下的 **Agentic AI Foundation**。

```
┌─────────┐    MCP 协议    ┌──────────┐
│  Agent   │ ◄──────────► │  MCP Server │
│ (Host)   │              │            │
│          │              │ ├── Database│
│          │              │ ├── Files   │
│          │              │ ├── API     │
│          │              │ └── Search  │
└─────────┘              └──────────┘
```

**架构意义**：MCP 将工具接口从"厂商锁定"推向**标准化**，使任何 MCP-compatible 的 Agent 都能自动发现和调用工具。

### 7.2 A2A（Agent-to-Agent Protocol）

Google 于 2025 年 4 月发布，定位在 **Agent 与 Agent 之间**的通信协议。2025 年 6 月贡献给 Linux 基金会。

```
                ┌──────────────┐
                │ Orchestrator  │
                │    Agent      │
                └──────┬───────┘
          A2A  ┌───────┴────────┐
        ┌──────▼────┐   ┌──────▼────┐
        │ Agent A   │   │ Agent B   │
        │ (MCP工具)  │   │ (MCP工具)  │
        └───────────┘   └───────────┘
```

**MCP vs A2A 的关系**：

| 协议 | 解决的问题 | 方向 |
|------|-----------|------|
| **MCP** | Agent 如何访问工具和数据 | 上下层连接 |
| **A2A** | Agent 之间如何协作通信 | 平行连接 |

### 7.3 协议栈全景（2025–2026）

```
Agent-to-Agent (A2A) ← Agent 间协作层
       ↕
   Agent 核心（推理+规划+执行）
       ↕
Model Context Protocol (MCP) ← 工具/数据接入层
       ↕
  数据库 | 文件 | API | 搜索 | 代码
```

---

## 八、2025–2026 架构前沿

### 8.1 深度推理 Agent（Deep Research）

OpenAI 的 **Deep Research** 和类似的深度研究 Agent 架构：

```
User Query → [Search Loop]
               ├── 规划搜索策略
               ├── 并行多源搜索（Web + Academic + Code）
               ├── 阅读 + 提取关键信息
               ├── 交叉验证冲突信息
               └── 是否足够？→ 是 → 合成报告
                                    ↓
                             报告生成（带引用）
```

核心架构特征：
- **多层搜索规划**：BFS 式探索
- **信息到报告的直接转换**：减少中间损耗
- **引用锚定（Citation Anchoring）**：免幻觉的可溯源设计

### 8.2 Agentic RAG（检索增强生成 + Agent 决策）

Agentic RAG 将传统 RAG 的"一阶段检索+生成"升级为**多策略决策**：

```
Query
  ↓
Router（路由决策）
├──→ Vector Search（语义检索）
├──→ Web Search（实时网络搜索）
├──→ SQL Query（结构化数据）
└──→ Agent Loop（复杂查询：分解→检索→合成）
```

### 8.3 Hermes Agent 自身的架构（Mirror of the Trend）

你正在对话的 Hermes Agent 本身也体现了当前架构设计的最新趋势：

- **工具中心**：所有工具（web_search, browser, terminal, execute_code 等）通过工具注册表暴露
- **ReAct Loop**：Thought（推理）→ Action（工具调用）→ Observation（结果回注）的自然循环
- **Skills = 过程记忆**：将可复用的工作流编码为 skill（类似 SOAR 的 Chunking）
- **Memory 系统**：持久记忆（跨 session）+ 会话搜索（短时上下文检索）
- **MCP 原生支持**：通过 Native MCP 技能连接标准协议工具
- **Subagent 架构**：delegate_task 实现多 Agent 并行协作（类似 AutoGen 模式）
- **Cron Job**：事件驱动的自主执行

---

## 九、架构演变总览图

```
1950s──┐
       ├── 专家系统（规则引擎）
1960s──┘
       │
1980s  ├── BDI（信念-愿望-意图）
       ├── SOAR（通用认知架构 / 决策周期 + Chunking）
       └── ACT-R（认知建模 + 亚符号层）
       │
1990s  ├── MDP + Q-Learning（经典RL）
       ├── 多Agent系统理论
2000s──┘
       │
2013   ├── DQN（深度RL / 经验回放）
2016   ├── PPO（Actor-Critic / 策略优化）
2017───┴── MADDPG（CTDE / 多Agent协作）
       │
2021   ├── WebGPT（语言模型 + 浏览器）
2022───┴── ChatGPT + 第三方插件
       │
2023-03├── AutoGPT / BabyAGI（任务分解 + 循环）
2023-06├── GPT-4 Function Calling（工具调用原生化）
2023-10├── ReAct（推理-行动闭环）
2023-12├── LangChain / LangGraph（链→图 / 状态机）
2024    ├── AutoGen / CrewAI（多Agent编排）
        ├── Reflexion（自我反思 + 经验回放）
2024-11 ├── MCP（工具/数据协议标准化）
2025-04 ├── A2A（Agent间通信协议）
2025-06 ├── Deep Research（深度推理检索）
2025-12 ├── MCP捐赠至Agentic AI Foundation
2026    └── 多范式融合：符号规则 + LLM 推理 + RL 反馈
```

---

## 十、核心洞察与结论

1. **从封闭到开放**：Agent 架构从封闭的符号规则系统，演化为通过协议（MCP/A2A）开放互联的生态系统。

2. **从单一体到协作体**：单一 LLM Agent → 多 Agent 编排（Orchestration）→ Agent 联邦（Federation）。

3. **循环结构是永恒模式**：从 SOAR 的决策周期到 ReAct 的 Thought-Action-Observation，循环感知-推理-执行架构是所有 Agent 系统的基础。

4. **记忆系统分层化**：Working Memory（Scratchpad）→ Short-term（对话历史）→ Long-term（向量数据库）的三层架构成为事实标准。

5. **编排粒度的细化**：从 Sequential Chain → State Graph → Multi-Agent Conversation → Role-based Team，编排抽象层次不断上升。

6. **"大脑"与"四肢"分离**：LLM 作为推理核心 → 工具作为执行层 → 协议作为连接层，三者走向解耦与标准化。

7. **评估-反馈-学习闭环**：Reflexion、RLHF、SFT from Agent Trajectory… Agent 正在从"一次执行"走向"自我进化"。

8. **当前的瓶颈**：Agent 可靠性（一致性幻觉）、成本控制（token 堆积）、安全边界（工具调用权限）、调试/可观测性——这些是 2025–2026 年的核心工程挑战。