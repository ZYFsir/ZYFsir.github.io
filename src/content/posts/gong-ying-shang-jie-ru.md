---
title: 供应商接入
description: pi-ai 就是 pi agent的供应商接入包，就连deepseek harness，底层也是使用这个包实现。
pubDatetime: 2026-09-24T02:35:01.000Z
tags: []
---

<!-- 由 blog-publish 自动生成，请勿手工编辑。源文件: 博客/供应商接入.md -->

pi-ai 就是 pi agent的供应商接入包，就连deepseek harness，底层也是使用这个包实现。

市面上有三种ai 的api协议：

- **Anthropic Messages**：Claude 的协议，system 是顶级字段，thinking 是一块独立的内容块；
- **OpenAI Chat Completions（旧）**：最普及，`messages` 数组 + `max_tokens`；
- **OpenAI Responses（新）**：GPT-5 时代的协议，`reasoning.effort`、developer 角色等。

\[这里需要补充三种协议的官方规定的模板，使用中文给出每个字段的内容描述，以及提供相关规范的官方定义链接\]

**pi-ai 解决的核心问题**：这三种协议对「同一段对话」的描述方式完全不同。比如一条「带思考过程、调用了工具的助手消息」：

- Anthropic 里它是 `content` 数组里的 `thinking` 块和 `tool_use` 块；
- OpenAI Chat 里它是 `reasoning_content` 字段 + `tool_calls` 数组；
- Responses 里它是输出列表里的 `reasoning` 项和 `function_call` 项。

\[这段文字描述的举例其实看不懂，比如块跟字段跟项有什么区别，希望插入模板后能看得懂\]

如果 agent 代码直接面向某一种协议写，换供应商就等于重写一遍。pi-ai 的做法是：**在三种协议之上，再定义一种"中间格式"，让 agent 只跟中间格式打交道**。

## **pi-ai 的四层结构**

### **第 1 层：归一化的对话格式（Transcript）**

pi-ai 定义了自己的消息模型，与任何供应商无关。一段对话就是一串消息：user、assistant、toolResult、system 每种角色都是统一的结构，assistant 消息的内容是块数组（text / thinking / toolCall 块），工具定义用 JSON Schema。

关键设计：这个 `Context` 就是普通 JSON 数据，没有任何函数挂在上面，可以直接存盘、传给别人。这一条支撑了它一个很亮眼的能力——**跨供应商交接**：同一段对话，前半段用 Claude 跑，后半段把上下文原封不动交给 GPT-5 继续。切换时唯一要做的转换是：别的供应商留下的 thinking 块，转换成 `<thinking>...</thinking>` 包裹的文本（因为别的协议不认识 thinking 块），文本和工具调用原样保留。

### **第 2 层：统一的事件流（Stream Events）**

三种协议的服务器都在往外推 SSE 数据块，但格式各异。pi-ai 把「模型正在输出」这件事抽象成一套固定事件：

\[SSE数据块是什么\]

**plain**

```plain
start → text_delta / thinking_delta / toolcall_delta … → done
```

不管底层是 Anthropic 的 `content_block_delta`、OpenAI 的 `choices[0].delta` 还是 Gemini 的 `candidates[0].content.parts`，每个 API 实现负责把原生事件**翻译**成上面这套事件。你的 UI/代码只需要处理一套事件，就自动支持所有供应商。工具调用的 JSON 参数在流式传输中还会被增量解析，让你实时看到模型正在填什么参数。

### **第 3 层：API 实现（真正发请求的地方）**

这就是你说的三种格式的落点，但不止三种。pi-ai 内置了这些线协议实现，每个模块导出固定的 `stream` / `streamSimple` 两个函数：

\[线协议是什么\]

**表格**

| **API 实现** | **服务谁** |
| --- | --- |
| `anthropic-messages` | Anthropic 官方，以及所有"Anthropic 兼容"端点（比如 Kimi For Coding） |
| `openai-completions` | OpenAI 旧协议，以及 xAI、Groq、Cerebras、OpenRouter、Ollama、vLLM 等一大批"OpenAI 兼容"端点 |
| `openai-responses` | OpenAI 官方新协议 |
| `google-generative-ai` / `google-vertex` | Gemini 的两个入口 |
| `azure-openai-responses`、`openai-codex-responses`、`mistral-conversations`、`bedrock-converse-stream` | 其余各家的原生协议 |

**注意这层的两个设计决策**：

1. **实现按协议分，不按品牌分**。30 多个内置供应商（OpenRouter、Groq、DeepSeek……）根本不需要自己的实现——它们说 `openai-completions`，就直接复用那一个实现。新接一个 OpenAI 兼容的网关，零新代码。这就是多供应商扩展性的关键：不是「每一家写一个适配器」，而是「N 个协议实现 × M 个供应商配置」。
2. **SDK 懒加载**。每个协议实现对应官方 SDK（`@anthropic-ai/sdk`、`openai`、`@google/genai`……），通过动态 import 包装，只有第一次真正请求该协议的模型时才加载对应 SDK。你只注册一个供应商，打包产物里就只带一个 SDK。

### **第 4 层：Provider（运行时单元）+ Models 集合**

这是最容易混淆的一层，值得用类比：**API 实现是"翻译器"（懂某种语言的 wire protocol），Provider 是"供应商专柜"（带着自己的商品目录、收银方式和发票规则）**。

一个 Provider 拥有三样东西：

- **模型目录（catalog）**：一个静态数据表，记录这家有哪些模型、上下文窗口、价格、是否支持 vision/reasoning、说哪种协议（`api` 字段）。这份目录是代码生成的（从 models.dev 等数据源脚本拉取），纯数据；
- **认证（auth）**：API key 怎么来——环境变量、已存储的凭据、OAuth 登录（如 Claude 订阅、Copilot 订阅的 OAuth flow），以及 token 过期自动刷新（带锁，防止并发请求重复刷新）；
- **API 实现引用**：通常就是一个懒加载的翻译器。

而 **Models 集合**是路由层：你调用 `models.getModel('anthropic', 'claude-sonnet-4-5')`，它找到 owning provider；调用 `models.stream(model, context)` 时，它先做 auth 解析、合并 header，再把请求分发给该模型声明的那个 API 实现。

有些供应商是**混合协议**的（比如 GitHub Copilot 同时卖 GPT 系和 Claude 系模型），它的 provider 带一个 `api` 映射表，**按模型逐个分发**到不同协议实现。

## 供应商验证

```
                    Provider 的 auth
                         │
        ┌────────────────┼─────────────────────┐
   显式 apiKey      CredentialStore           环境变量
   (单次调用)      ┌──────────────┐        (兜底)
                  │ API key 凭据  │ ← 简单，复制来的
                  │ OAuth 凭据    │ ← 复杂的那个:
                  │  accessToken  │    login() 走一次交互授权
                  │  refreshToken │    refresh() 过期自动换新(加锁)
                  └──────────────┘    toAuth() 变成请求 header
                         │
                    每次请求解析出 headers
```

OAuth是针对帐号订阅类的供应商的验证手段，需要定期登录来更新密钥。