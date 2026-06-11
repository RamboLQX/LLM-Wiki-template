# Paper Ingest Skill

论文深度阅读与知识提取。将学术论文转化为 6 节结构化报告，并融入 LLM Wiki 知识网络。

## 触发条件

**单篇处理**（用户执行以下任一操作时）：
- 说"读这篇论文""处理这篇论文""ingest paper""分析这篇论文"
- 使用 `/paper-ingest` 命令
- 说"处理 raw/papers/ 下的 xxx"（指向单个文件）

**批量处理**（用户执行以下任一操作时）：
- 说"处理这个文件夹下的文章""批量处理 raw/papers/xxx"
- 说"把这批论文都处理了"
- 使用 `/paper-ingest` 并指向一个文件夹

## 前置条件

用户需要先将论文 PDF 放入 `raw/papers/` 目录。如果没有，先引导用户放入。

---

# 单篇处理模式

采用**轻量主会话（Lightweight Main Session）**模式：主会话只做调度，论文全文和报告生成全在 Workflow 内部完成，主会话仅接收一段短摘要。

```
Step 0: 主会话 — pdftotext 提取论文文本 → 写入临时文件
Step 1: 主会话 — 构建 KB 上下文（搜索 wiki 中相关论文，仅提取摘要）
Step 2: 主会话 — 启动 Workflow，传入临时文件路径 + KB 上下文
         └─ Workflow Phase 1: 5 agent 并行，各自直接读取论文全文 → Section 1-5
         └─ Workflow Phase 2: 1 agent 合成 → Section 6
         └─ Workflow Phase 3: 3 agent 并行 → 写入报告 + 实体页 + 概念页
         └─ Workflow Phase 4: 1 agent → 更新 index + log
         └─ 返回：仅一段 300 字以内的操作摘要
Step 3: 主会话 — 接收摘要，向用户汇报
```

**核心原则**：
- 论文原文（通常 50-150KB）**不进主会话上下文**，仅在 Workflow 内部 agent 中读取
- 完整报告直接在 Workflow 内部写入磁盘，**不回流传主会话**
- 主会话只拿到 ~300 字摘要，每篇论文消耗主上下文 < 5%
- **无串行瓶颈**：5 个 section agent 各自直接从论文原文读取，无需等待前置 reader agent

---

## Step 0: PDF 文本提取（主会话，轻量）

### 论文来源确认

先确认用户要处理哪篇论文。如果用户没有明确指定：
- 检查目标目录下是否有新文件
- 列出可选论文让用户选择
- 如果没有 PDF，提示用户先放入

### PDF 文本提取（使用 pdftotext）

**重要**：不要用 Read 工具读取 PDF（会将 PDF 页作为图片加载到主会话上下文，非常重）。改用 `pdftotext` 命令行提取纯文本，写入临时文件。

```bash
pdftotext -layout "论文路径.pdf" /tmp/paper_ingest.txt
```

- 论文原文写入 `/tmp/paper_ingest.txt`（不进主会话上下文）
- 用 `wc -l` 确认行数，用 `wc -c` 确认大小
- 如果文件过大（>200KB），考虑用 `head -n 500` 截断引言/结论以外的内容（相关工作的引用列表通常价值很低）
- 主会话中**不 Read 这个文件**——只把文件路径传给 Workflow

### 提取元数据（可选）

直接从文件名提取作者、年份等信息。如有 arXiv ID，可在 Workflow 内部让 agent 从论文原文中解析。

---

## Step 1: 构建 KB 上下文（主会话，轻量）

搜索 wiki 中已有的相关论文，为 Section 4（相关工作比较）提供上下文。此步骤在主会话完成，只提取已有报告的元数据和核心观点，不读取完整报告。

### 构建方法

1. 读取 `wiki/index.md`，获取 sources 分类下所有已有论文报告
2. 对每篇已有论文报告，读取其 frontmatter 和"核心观点"部分（或前 50 行）
3. 根据标题、摘要、核心方法名与当前论文做相关性匹配
4. 选取 top 3-5 篇最相关的已有论文
5. 格式化为 KB 上下文段落（≤1000 字），以纯文本形式传入 Workflow：

```
## 知识库上下文（已读论文，可用于对比）

- **[[wiki/sources/已有论文报告名|论文标题]]** (年份, 会议/期刊)
  核心内容: [从已有报告的核心观点部分提取，≤200 字]

- **[[wiki/sources/另一篇|另一篇标题]]** (年份, 会议/期刊)
  核心内容: [摘要]
```

如果 wiki 中还没有相关论文，传入 `KB_EMPTY` 标记。

---

## Step 2: 启动 Workflow 生成报告并写入 Wiki（轻量）

主会话调用 Workflow，传入以下参数：
- `PAPER_PATH`: 临时文本文件路径（如 `/tmp/paper_ingest.txt`）
- `KB_CONTEXT`: KB 上下文文本（或 `KB_EMPTY`）
- `PAPER_FILE`: 原始 PDF 路径（用于命名）
- `TITLE`: 论文标题（从文件名推断或让 Workflow 内部解析）
- `VAULT_ROOT`: `{your_vault_path}`

Workflow 内部 4 阶段执行，**主会话不接触论文全文和完整报告**。各 section agent 直接从论文原文读取，无串行 reader 瓶颈。

### Workflow 脚本模板（V2：直读并行模式）

```javascript
export const meta = {
  name: 'paper-ingest-v2',
  description: '5 agents read paper directly in parallel → synthesize → 3 agents write in parallel → update index. No reader bottleneck.',
  phases: [
    { title: 'Analyze', detail: '5 parallel agents each read paper and write sections 1-5' },
    { title: 'Synthesize', detail: 'Section 6 from all previous sections' },
    { title: 'Write', detail: '3 parallel agents: report + entities + concepts' },
    { title: 'Index', detail: 'Update index and log' },
  ],
}

// ===== 从 args 中获取参数 =====
const PAPER_PATH = args.paperPath     // 临时文本文件路径
const KB_CONTEXT = args.kbContext     // KB 上下文或 "KB_EMPTY"
const PAPER_FILE = args.paperFile     // PDF 路径，用于命名
const TITLE = args.title
const VAULT_ROOT = args.vaultRoot
const TODAY = args.today              // "YYYY-MM-DD"

const paperSlug = PAPER_FILE.split('/').pop().replace('.pdf', '')

// ===== 共享 prompts =====
const KB_SECTION = KB_CONTEXT === 'KB_EMPTY'
  ? '\n## 知识库上下文\n暂无相关已读论文。\n'
  : '\n' + KB_CONTEXT + '\n'

const SYSTEM_PROMPT = `你是一位资深 AI 研究员，正在撰写一篇学术论文的深度阅读笔记。你的写作要求：

1. **精炼优先**：聚焦 3-5 个最核心的洞察，不追求面面俱到。详细分析每段不超过 200 字，优先使用要点列表呈现关键信息
2. 学术化中文，精准具体但简洁——删掉不必要的修饰和重复
3. 必须引用论文中的具体数字、公式、方法名来支撑观点，而非泛泛而谈
4. 解释设计动机，而不只是罗列方法
5. 做实质性对比分析，而非表面比较
6. 数学公式使用 $...$ 或 $$...$$ 格式
7. 知识库上下文（已读论文）如果提供了，必须在相关部分使用它进行对比
8. **避免**：逐段复述论文原文、冗余重复的论述、把笔记写成第二篇论文
9. **目标**：让读者 2 分钟内通过要点列表掌握本节 80% 的核心信息，详细分析补充剩余 20%`

const SECTION_FORMAT = `

**输出格式（必须严格遵循以下三层结构，不要写成一大块连续文本）：**

> 💡 **要点速览**：[用 1-2 句话直接给出本节最核心的结论]

**核心要点**（3-5 条，每条 ≤50 字，用要点列表）：
- [关键点1]
- [关键点2]
- ...

**详细分析**（精炼，不重复要点列表中已出现的结论）：
[分析文本]`

// ===== Phase 1: 5 agents 并行，各自直接从论文原文读取并撰写 =====
phase('Analyze')

const [q1, q2, q3, q4, q5] = await parallel([
  () => agent(`${SYSTEM_PROMPT}

请先使用 Read 工具读取论文文本文件（路径: \`${PAPER_PATH}\`），然后撰写论文《${TITLE}》的第一节：**研究问题与动机**。${SECTION_FORMAT}

内容要求（融入上述三层结构）：
- 阅读时重点关注论文的 introduction / motivation 部分
- 要点速览应直接回答"这篇论文要解决什么问题、为什么重要"
- 核心要点覆盖：领域背景、现有方法痛点、研究缺口、论文的核心研究主张
- 详细分析 200-350 字，解释为什么这个问题值得研究、论文的独特切入点是什么

${KB_SECTION}`, { label: 'sec1-问题动机' }),

  () => agent(`${SYSTEM_PROMPT}

请先使用 Read 工具读取论文文本文件（路径: \`${PAPER_PATH}\`），然后撰写论文《${TITLE}》的第二节：**核心方法**。${SECTION_FORMAT}

内容要求（融入上述三层结构）：
- 阅读时重点关注论文的 method / approach / architecture 部分
- 要点速览应直接回答"论文用什么方法解决问题、核心创新是什么"
- 核心要点覆盖：整体架构、关键创新点、核心公式（如有）、设计动机
- 详细分析 300-450 字，包含重要数学公式和关键参数，解释为什么这样设计

${KB_SECTION}`, { label: 'sec2-核心方法' }),

  () => agent(`${SYSTEM_PROMPT}

请先使用 Read 工具读取论文文本文件（路径: \`${PAPER_PATH}\`），然后撰写论文《${TITLE}》的第三节：**实验设计与结果**。${SECTION_FORMAT}

内容要求（融入上述三层结构）：
- 阅读时重点关注论文的 experiments / results / ablation 部分
- 要点速览应直接回答"实验验证了什么、最关键的发现是什么"
- 核心要点覆盖：数据集/任务、对比基线、关键数字（指标、提升幅度）、消融发现
- 详细分析 200-350 字，对实验可信度和说服力做出判断

${KB_SECTION}`, { label: 'sec3-实验设计' }),

  () => agent(`${SYSTEM_PROMPT}

请先使用 Read 工具读取论文文本文件（路径: \`${PAPER_PATH}\`），然后撰写论文《${TITLE}》的第四节：**与相关工作的比较**。${SECTION_FORMAT}

内容要求（融入上述三层结构）：
- 阅读时重点关注论文的 related work / discussion / comparison 部分
- 要点速览应直接回答"这篇论文与已有工作相比，最根本的区别是什么"
- 核心要点覆盖：与 KB 中已读论文的实质性对比、论文自身讨论的相关工作
- 详细分析 200-350 字，不要编造不存在的引用

${KB_SECTION}`, { label: 'sec4-相关工作' }),

  () => agent(`${SYSTEM_PROMPT}

请先使用 Read 工具读取论文文本文件（路径: \`${PAPER_PATH}\`），然后撰写论文《${TITLE}》的第五节：**局限性与未来工作**。${SECTION_FORMAT}

内容要求（融入上述三层结构）：
- 阅读时重点关注论文的 limitations / future work / conclusion / discussion 部分
- 要点速览应直接回答"这篇论文最关键的局限性是什么"
- 核心要点覆盖：作者承认的局限、未被提及的潜在问题、未来改进方向
- 详细分析 150-250 字

${KB_SECTION}`, { label: 'sec5-局限性' }),
])

// ===== Phase 2: 综合 agent（依赖 Phase 1 全部完成）=====
phase('Synthesize')

const q6 = await agent(`${SYSTEM_PROMPT}

请撰写论文《${TITLE}》的第六节：**我的评价与启发**。${SECTION_FORMAT}

你需要基于前五节的分析来进行综合判断。以下是前五节的内容：

---
## 1. 研究问题与动机
${q1 || '(未生成)'}

## 2. 核心方法
${q2 || '(未生成)'}

## 3. 实验设计与结果
${q3 || '(未生成)'}

## 4. 与相关工作的比较
${q4 || '(未生成)'}

## 5. 局限性与未来工作
${q5 || '(未生成)'}
---

内容要求（融入上述三层结构）：
- 要点速览应直接回答"这篇论文最值得记住的一个贡献或启发是什么"
- 核心要点覆盖：整体贡献评价（含 1-10 评分及一句话理由）、可迁移性判断、激发的具体研究想法
- 详细分析 150-250 字`, { label: 'sec6-评价启发' })

// ===== 组装报告正文（供 Phase 3 使用）=====
const REPORT_BODY = `
## 1. 研究问题与动机
${q1 || ''}

## 2. 核心方法
${q2 || ''}

## 3. 实验设计与结果
${q3 || ''}

## 4. 与相关工作的比较
${q4 || ''}

## 5. 局限性与未来工作
${q5 || ''}

## 6. 我的评价与启发
${q6 || ''}
`

// ===== Phase 3: 3 agents 并行写入 =====
phase('Write')

const [reportSummary, entitySummary, conceptSummary] = await parallel([
  // Agent A: 组装并写入来源报告
  () => agent(`你是 LLM Wiki 的维护 agent。请将以下论文报告写入 wiki。

## 任务
1. 从 6 节内容的"要点速览"中提取关键信息，生成快速预览表（格式见下方）
2. 将预览表 + 完整 6 节正文写入 \`${VAULT_ROOT}/wiki/sources/${paperSlug}.md\`

## 快速预览表格式（必须放在 # 标题之后、第一节之前）

从各节的 > 💡 要点速览 行提取信息填入以下表格，每格 1-2 句：

| 维度 | 内容 |
|------|------|
| 🎯 研究问题 | [从第1节要点速览提取] |
| 💡 核心方法 | [从第2节要点速览提取] |
| 📊 关键发现 | [从第3节要点速览提取] |
| ✨ 主要贡献 | [从第1、6节综合] |
| ⚠️ 主要局限 | [从第5节要点速览提取] |
| 🏆 总评 | **X/10** — [从第6节提取一句话理由] |

表格后紧跟 \`---\` 分隔线，然后是 6 节正文。**表格内容和各节要点速览必须一致。**

## 要写入的完整报告

\`\`\`markdown
---
tags: [source, paper]
created: ${TODAY}
updated: ${TODAY}
source-type: paper
arxiv: ""
authors: ""
published: ""
venue: ""
status: evergreen
---

# ${TITLE}

| 维度 | 内容 |
|------|------|
| 🎯 研究问题 | [待提取] |
| 💡 核心方法 | [待提取] |
| 📊 关键发现 | [待提取] |
| ✨ 主要贡献 | [待提取] |
| ⚠️ 主要局限 | [待提取] |
| 🏆 总评 | [待提取] |

---
${REPORT_BODY}

## 提取的实体与概念

<!-- 实体和概念页面由专门的 agent 并行处理 -->
\`\`\`

请填充预览表后写入文件。完成后返回一行摘要：写入的文件路径和报告评分（如"wiki/sources/xxx.md — 评分 X/10"）。`, { label: 'write-report' }),

  // Agent B: 创建/更新实体页面
  () => agent(`你是 LLM Wiki 的知识提取 agent。请从以下论文报告中提取关键**实体**并在 wiki 中创建/更新页面。

## 论文报告内容
${REPORT_BODY}

## 任务
1. 从报告中识别 3-8 个关键实体（方法名、模型名、数据集名、系统名等专有名词）
2. 对每个实体，检查 \`${VAULT_ROOT}/wiki/entities/\` 下是否已有页面（文件名包含该实体名即视为已有）
   - **已有页面**：在"关系"和"引用来源"小节中追加对本文的引用（不要覆盖原有内容）
   - **新页面**：使用以下模板创建

\`\`\`markdown
---
tags: [entity]
created: ${TODAY}
updated: ${TODAY}
sources:
  - "[[wiki/sources/${paperSlug}]]"
aliases: []
status: stub
---

# {实体名}

## 概述
[一段话定义，基于论文中的描述]

## 关键信息
- [从论文中提取的核心事实]

## 关系
- [相关实体/概念，带 wiki-link]

## 引用来源
- [[wiki/sources/${paperSlug}]]
\`\`\`

完成后返回摘要：列出新建和更新的实体页面名（逗号分隔）。`, { label: 'write-entities' }),

  // Agent C: 创建/更新概念页面
  () => agent(`你是 LLM Wiki 的知识提取 agent。请从以下论文报告中提取关键**概念**并在 wiki 中创建/更新页面。

## 论文报告内容
${REPORT_BODY}

## 任务
1. 从报告中识别 3-8 个关键概念（理论框架、方法范式、技术术语、评估指标等）
2. 对每个概念，检查 \`${VAULT_ROOT}/wiki/concepts/\` 下是否已有页面
   - **已有页面**：在"与其他概念的关系"和"引用来源"中追加对本文的引用
   - **新页面**：使用以下模板创建

\`\`\`markdown
---
tags: [concept]
created: ${TODAY}
updated: ${TODAY}
sources:
  - "[[wiki/sources/${paperSlug}]]"
aliases: []
status: stub
---

# {概念名}

## 定义
[清晰的概念定义，基于论文中的描述]

## 核心要点
- [关键理解点，列表形式]

## 与其他概念的关系
- [区分、联系、层级]

## 应用与示例
- [论文中的实际案例]

## 引用来源
- [[wiki/sources/${paperSlug}]]
\`\`\`

完成后返回摘要：列出新建和更新的概念页面名（逗号分隔）。`, { label: 'write-concepts' }),
])

// ===== Phase 4: 更新 index 和 log =====
phase('Index')

const finalSummary = await agent(`你是 LLM Wiki 的维护 agent。请更新索引和日志。

## 已知信息
- 论文报告文件：\`wiki/sources/${paperSlug}.md\`
- 实体操作结果：${entitySummary || '(无)'}
- 概念操作结果：${conceptSummary || '(无)'}
- 论文标题：${TITLE}
- 日期：${TODAY}

## 第 6 节评价（用于获取评分和核心贡献）
${q6 || '(未生成)'}

## 任务

### 1. 更新 wiki/index.md
读取 \`${VAULT_ROOT}/wiki/index.md\`，在对应分类下添加新条目：
- **来源**：\`- [[wiki/sources/${paperSlug}|${TITLE}]] — [一句话描述核心贡献]\`
- **实体**：根据 entitySummary 中列出的实体名添加条目
- **概念**：根据 conceptSummary 中列出的概念名添加条目
注意：只添加新条目，不要覆盖已有的不相关条目。

### 2. 追加 wiki/log.md
读取 \`${VAULT_ROOT}/wiki/log.md\`，在末尾追加一条日志记录：

\`\`\`markdown
## [${TODAY}] ingest paper | ${TITLE}

- 新建来源：[[wiki/sources/${paperSlug}]]（6-section 深度报告）
- 新建实体：[从 entitySummary 提取]
- 新建概念：[从 conceptSummary 提取]
- 摘要：[一句话总结核心贡献和评分]
\`\`\`

## 完成后
返回一段简短的操作摘要（≤300 字），列出：
- 报告写入的文件名和评分
- 新建/更新了哪些页面
- 是否有值得注意的发现`, { label: 'update-index-log' })

// ===== 只返回摘要给主会话 =====
return {
  summary: finalSummary || '报告已写入 wiki',
  reportFile: `wiki/sources/${paperSlug}.md`,
}
```

### Workflow 调用方式

主会话中的调用代码：

```javascript
// Step 0: 提取论文文本
// Bash: pdftotext -layout "论文.pdf" /tmp/paper_ingest.txt

// Step 1: 构建 KB 上下文
// 读取 wiki/index.md → 筛选相关论文 → 提取核心观点 → 格式化为 KB_CONTEXT

// Step 2: 启动 Workflow
Workflow({
  script: `...上述脚本模板...`,
  args: {
    paperPath: "/tmp/paper_ingest.txt",
    kbContext: KB_CONTEXT || "KB_EMPTY",
    paperFile: "{your_vault_path}/raw/papers/论文名.pdf",
    title: "论文标题",
    vaultRoot: "{your_vault_path}",
    today: "2026-06-02"
  }
})

// Step 3: 接收 result.summary，向用户汇报
```

### 统一 System Prompt 和各 Section Prompt

已嵌入上述 Workflow 脚本模板中，无需单独维护。核心要求摘要：

- **直接读原文**：每个 section agent 使用 Read 工具直接从论文文本文件中读取，按各自 section 的视角提取信息（如 Section 1 agent 重点关注 introduction/motivation 部分），无需等待前置 reader
- **输出格式**：每节统一使用三层结构 — 💡 要点速览（1-2句）→ 核心要点（3-5条要点列表）→ 详细分析
- **快速预览表**：报告顶部必须包含一个 6 行摘要表格（研究问题/核心方法/关键发现/主要贡献/主要局限/总评），由 report writer agent 从各节提取生成
- System Prompt: 精炼优先、学术化中文、具体数字/公式/方法名、设计动机、实质性对比；每段不超过 200 字
- Section 1: 详细分析 200-350 字，领域背景 + 现有痛点 + 研究主张
- Section 2: 详细分析 300-450 字，架构 + 创新点 + 公式 + 设计动机
- Section 3: 详细分析 200-350 字，数据集 + 基线 + 关键数字 + 消融分析
- Section 4: 详细分析 200-350 字，KB 对比 + 论文自述相关工作
- Section 5: 详细分析 150-250 字，作者局限 + 分析者视角问题 + 改进方向
- Section 6: 详细分析 150-250 字，贡献定位 + 可迁移性 + 研究启发 + 评分

---

## Step 3: 主会话收尾（轻量）

Workflow 完成后，主会话接收约 300 字的操作摘要。向用户汇报：

- 点击 `[[wiki/sources/报告文件名]]` 查看完整报告
- 新建/更新了哪些页面（从摘要中提取）
- 报告评分
- 是否有值得注意的发现（如与已有 wiki 内容的矛盾）

---

# 批量处理模式

当用户说"处理这个文件夹""批量处理这些论文"时，采用递进式 KB 上下文的批量模式。核心区别于单篇：

1. **全部论文共享递进式 KB**：每篇处理完后刷新 KB，下一篇的 Section 4 能看到前面所有已处理论文
2. **按理论深度排序**：框架/理论类 → 方法/应用类 → 领域外围类
3. **已处理自动跳过**：检查 `wiki/sources/` 下已有报告则跳过

## 批量流程总览

```
Step B0: 扫描文件夹 → 识别 PDF → 过滤已处理 → 排序
Step B1: 批量提取全部论文文本到临时文件
Step B2: 构建初始 KB 上下文（已有 wiki 知识 + 领域背景）
Step B3: 逐篇循环 {
          当前 KB 上下文 → 启动单篇 Workflow（复用单篇模板）
          → 等待完成 → 汇报单篇摘要
          → 刷新 KB（读入刚写入报告的 frontmatter + 核心观点）
        }
Step B4: 批量收尾（总体汇报 + 交叉引用质量检查）
```

## Step B0: 扫描文件夹

```bash
# 列出目标文件夹下所有 PDF
ls "目标文件夹"/*.pdf
```

对每个 PDF：
1. 提取文件名（去 .pdf 后缀）作为 paper slug
2. 检查 `wiki/sources/${slug}.md` 是否存在 → 存在则标记为「已处理」，跳过
3. 用 `pdftotext -l 3` 提取前 3 页快速判断论文主题

### 排序策略

按以下优先级排序论文处理顺序：

| 优先级 | 类别 | 特征 |
|--------|------|------|
| 🔴 先处理 | 框架/理论/分类法 | 提出新分类体系、理论框架、全面基准 |
| 🟡 中间 | 方法/特定场景 | 解决特定冲突类型的系统/方法 |
| 🟢 最后 | 领域外围/弱相关 | 侧重点不在核心主题，在特定领域应用 |

排序目标：让后面的论文能在 Section 4 中引用前面的论文，形成知识层积。

### 跳过已处理论文

对比 `wiki/sources/` 下已有文件名与 PDF 文件名。匹配则自动跳过，在汇报中标注「已处理，跳过」。

## Step B1: 批量提取文本

对每篇未处理的论文：

```bash
pdftotext -layout "论文路径.pdf" "/tmp/paper_ingest_${slug}.txt"
```

- 每篇论文独立一个临时文件，命名带 slug 区分
- 记录每篇论文的文件大小，过大的（>200KB）在 Workflow 内部由 reader agent 自行截断

## Step B2: 构建初始 KB 上下文

与单篇 Step 1 相同，但额外加入**该文件夹/主题的整体定位描述**：

```
## 知识库上下文（用于 Section 4 相关工作比较）

### 本批次论文主题
[一段话描述这批论文的共同主题，如"知识冲突评估框架"——涵盖冲突检测、分类、解析、
评估的完整 pipeline，涉及 RAG、多模态、跨语言、领域特化等多个维度]

### 已有 wiki 知识
- **[[wiki/sources/已处理论文A]]** (年份, 会议)
  核心内容: [≤200 字]

- **[[wiki/entities/ConflictBank]]** — [简要说明]
...
```

## Step B3: 递进式循环

对每个待处理论文（按 B0 排序后的顺序）：

```
1. 提取当前论文文本到临时文件（如果 B1 尚未做）
2. 将当前 KB_CONTEXT 传入 Workflow（复用 §Step 2 的脚本模板）
3. 启动 Workflow，等待完成
4. 从 Workflow 接收 result.summary，向用户汇报单篇结果
5. 刷新 KB 上下文：
   a. 读取刚写入的 wiki/sources/${slug}.md 的 frontmatter + 第 6 节评分 + 核心观点
   b. 追加到 KB_CONTEXT（格式与初始 KB 一致）
   c. 如果该论文引入了新实体/概念，简要记录供后续论文对比
```

### KB 上下文刷新格式

每篇论文处理完后，追加以下内容到 KB_CONTEXT：

```
- **[[wiki/sources/${slug}|标题]]** (年份, 会议) 评分: X/10
  核心贡献: [从第 1 节和第 6 节提炼，≤150 字]
  关键方法/概念: [方法名1], [概念1], ...
```

注意：刷新后的 KB_CONTEXT 总长度控制在 3000 字以内。如果超过，优先保留评分高的论文引用和核心框架类论文。

## Step B4: 批量收尾

全部论文处理完毕后，生成一份批量处理总结：

1. **处理统计**：总共 N 篇，新处理 M 篇，跳过 K 篇（已处理）
2. **报告列表**：每篇的 wiki link + 评分 + 一句话
3. **交叉引用检查**：检查新写入的报告是否在 Section 4 中引用了同批次其他论文（质量指标）
4. **知识网络更新概要**：新建/更新了哪些实体和概念页面

---

# 与 LLM Wiki 框架的关系

本 skill 是 LLM Wiki 框架中"论文"类型来源的专用 Ingest 通道。它遵循 AGENTS.md 中定义的所有 wiki 规范（页面格式、frontmatter、链接规范、lint 规则等），只是在"来源消化"环节使用了更深度的结构化分析。

当用户同时使用本 skill 和通用 ingest 时（例如一篇论文 + 一篇博客），所有输出统一存储在 `wiki/` 下，共享同一套索引、日志和知识网络。

---

# 注意事项

- **V2 直读并行模式**：5 个 section agent 各自直接从论文原文读取并撰写，无串行 reader 瓶颈。Token 消耗上升（5 次全文读取 vs 1 次），但 wall-clock 显著缩短（预计减少 40-50%），因为不再等待前置 reader agent
- **主会话始终轻量**：论文原文不进主会话，所有重活（读取、分析、写入）在 Workflow 内部完成。主会话只做调度和汇报，每篇仅收到 ~300 字摘要
- Skill 只处理论文 PDF。对于非论文内容（文章、博客、书籍笔记），使用 AGENTS.md 中定义的通用 Ingest 工作流
- **PDF 文本提取**：使用 `pdftotext -layout` 而非 Read 工具（后者会以图片形式加载，消耗大量上下文）
- 如果论文过长导致文本文件 >200KB，在 `pdftotext` 后用 `head` 截断（保留引言到结论部分，去掉参考文献列表的冗余行）
- 如果 Workflow 工具不可用，退回串行模式（先 5 次独立 section agent 调用、再 Section 6 合成、再串行写入）。串行模式下论文原文会进入主会话，仅适合单篇处理
- 所有输出文件使用相对路径（从 vault 根目录）
- 知识提取环节不要贪多——只提取论文中真正核心且有 wiki 价值的实体和概念

### 批量模式额外注意事项

- **已处理检测只依赖文件名匹配**：如果论文标题相同但 PDF 文件名不同，需手动判断
- **排序不是绝对的**：如果用户有明确的处理顺序偏好，以用户指定为准
- **递进式 KB 刷新是质量关键**：每篇处理完后务必刷新，否则后面的论文 Section 4 会缺少上下文
- **中途中断可恢复**：已处理的论文报告已写入磁盘，恢复时只需处理剩余论文
- **单次批量建议不超过 15 篇**：超出后 KB 上下文过长，且主会话可能超时
