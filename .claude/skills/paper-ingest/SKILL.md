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
         └─ Workflow Phase 0: 1 agent 读取论文全文 → 生成结构化摘要
         └─ Workflow Phase 1: 5 agent 并行 → Section 1-5
         └─ Workflow Phase 2: 1 agent 合成 → Section 6
         └─ Workflow Phase 3: 1 agent 写入所有 wiki 文件 + 更新 index/log
         └─ 返回：仅一段 500 字以内的操作摘要
Step 3: 主会话 — 接收摘要，向用户汇报
```

**核心原则**：
- 论文原文（通常 50-150KB）**不进主会话上下文**，仅在 Workflow 内部 agent 中读取
- 完整报告直接在 Workflow 内部写入磁盘，**不回流传主会话**
- 主会话只拿到 ~500 字摘要，每篇论文消耗主上下文 < 5%

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
- `VAULT_ROOT`: `{your_vault_path}`（如 `/Users/yourname/obsidian`）

Workflow 内部 4 阶段执行，**主会话不接触论文全文和完整报告**。

### Workflow 脚本模板（轻量主会话模式）

```javascript
export const meta = {
  name: 'paper-ingest-lightweight',
  description: 'Read paper → analyze → write wiki — all inside workflow, return only summary',
  phases: [
    { title: 'Read', detail: '1 agent reads paper, produces structured summary' },
    { title: 'Analyze', detail: '5 parallel agents for sections 1-5' },
    { title: 'Synthesize', detail: 'Section 6 from all previous sections' },
    { title: 'Write', detail: 'Write report + entity/concept pages + update index/log' },
  ],
}

// ===== 从 args 中获取参数 =====
const PAPER_PATH = args.paperPath     // 临时文本文件路径
const KB_CONTEXT = args.kbContext     // KB 上下文或 "KB_EMPTY"
const PAPER_FILE = args.paperFile     // PDF 路径，用于命名
const TITLE = args.title
const VAULT_ROOT = args.vaultRoot
const TODAY = args.today              // "YYYY-MM-DD"

// ===== Phase 0: 阅读论文 + 生成结构化摘要 =====
phase('Read')

const paperSummary = await agent(`
你是一位论文预处理专家。请读取论文文本文件并生成一份结构化的内容摘要。

论文文件路径: ${PAPER_PATH}

请用 Read 工具读取该文件，然后生成以下格式的摘要（中文，尽量详细）：

## 论文元数据
- 标题、作者、机构、发表时间/会议、arXiv ID（如果论文中有）

## 摘要
[论文 abstract 的翻译或总结，100-200 字]

## 核心方法
[详细描述，包含关键公式和参数，≥300 字]

## 实验设置与关键结果
[数据集、基线、主要数字，≥200 字]

## 相关工作分类
[论文如何组织 related work，列出关键对比的文献]

## 附录要点
[附录中的重要补充信息]

注意：
- 保留所有重要公式（$...$ 格式）
- 保留所有关键数字（百分比、参数规模等）
- 不需要保留完整的参考文献列表
- 总字数控制在 2000 字以内
`, { label: 'reader' })

const KB_SECTION = KB_CONTEXT === 'KB_EMPTY'
  ? '\n## 知识库上下文\n暂无相关已读论文。\n'
  : '\n' + KB_CONTEXT + '\n'

const SYSTEM_PROMPT = `你是一位资深 AI 研究员，正在撰写一篇学术论文的深度阅读笔记。你的写作要求：

1. 使用学术化的中文，精准、具体、有深度
2. 必须引用论文中的具体数字、公式、方法名——不要泛泛而谈
3. 解释设计动机，而不只是罗列方法
4. 做实质性对比分析，而非表面比较
5. 数学公式使用 $...$ 或 $$...$$ 格式
6. 每个段落不少于 200 字
7. 知识库上下文（已读论文）如果提供了，必须在相关部分使用它进行对比`

// 构建 section 1-5 的 prompts（使用 paperSummary 而非全文）
const S1 = `${SYSTEM_PROMPT}\n\n请撰写论文《${TITLE}》的第一节：**研究问题与动机**。\n\n要求：\n1. 阐述该研究所属的领域背景和核心问题\n2. 分析现有方法在该问题上的痛点和不足\n3. 说明为什么这个问题重要且值得研究\n4. 清晰陈述论文的核心研究主张（thesis statement）\n5. 不少于 200 字\n\n论文内容摘要：\n${paperSummary}\n${KB_SECTION}`

const S2 = `${SYSTEM_PROMPT}\n\n请撰写论文《${TITLE}》的第二节：**核心方法**。\n\n要求：\n1. 描述整体架构或方法论框架\n2. 指出关键创新点（与现有方法的核心区别）\n3. 尽可能包含重要的数学公式和关键参数设置\n4. 解释训练策略、损失函数设计、推理流程等实现要点\n5. 阐述设计背后的动机——为什么这样设计\n6. 不少于 300 字\n\n论文内容摘要：\n${paperSummary}\n${KB_SECTION}`

const S3 = `${SYSTEM_PROMPT}\n\n请撰写论文《${TITLE}》的第三节：**实验设计与结果**。\n\n要求：\n1. 列举使用了哪些任务/数据集进行评估\n2. 列出对比的基线方法及选择理由\n3. 报告关键实验数字（指标、百分比、提升幅度）\n4. 分析消融实验的发现（如果有）\n5. 对实验结果的可信度和说服力做出判断\n6. 不少于 200 字\n\n论文内容摘要：\n${paperSummary}\n${KB_SECTION}`

const S4 = `${SYSTEM_PROMPT}\n\n请撰写论文《${TITLE}》的第四节：**与相关工作的比较**。\n\n要求：\n1. 首先使用"知识库上下文"中列出的已读论文进行实质性对比（如果KB上下文为空则跳过此步）\n2. 然后分析论文自身讨论的相关工作\n3. 不要编造不存在的引用\n4. 不少于 200 字\n\n论文内容摘要：\n${paperSummary}\n${KB_SECTION}`

const S5 = `${SYSTEM_PROMPT}\n\n请撰写论文《${TITLE}》的第五节：**局限性与未来工作**。\n\n要求：\n1. 列出论文作者自己承认的局限性\n2. 从你的分析视角，指出论文可能未提及的潜在问题\n3. 提出具体的未来改进方向\n4. 不少于 150 字\n\n论文内容摘要：\n${paperSummary}\n${KB_SECTION}`

// ===== Phase 1: 5 agents in parallel =====
phase('Analyze')

const [q1, q2, q3, q4, q5] = await parallel([
  () => agent(S1, { label: 'sec1-问题动机' }),
  () => agent(S2, { label: 'sec2-核心方法' }),
  () => agent(S3, { label: 'sec3-实验设计' }),
  () => agent(S4, { label: 'sec4-相关工作' }),
  () => agent(S5, { label: 'sec5-局限性' }),
])

// ===== Phase 2: synthesis agent =====
phase('Synthesize')

const q6 = await agent(`${SYSTEM_PROMPT}

请撰写论文《${TITLE}》的第六节：**我的评价与启发**。

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

要求：
1. 评价论文的整体贡献和在领域中的定位
2. 判断该方法的可迁移性
3. 提出该论文激发的具体研究想法
4. 给出一个总体评分（1-10 分）并简要说明理由
5. 不少于 150 字

论文内容摘要：
${paperSummary}`, { label: 'sec6-评价启发' })

// ===== Phase 3: Write everything to wiki =====
phase('Write')

// 从论文路径提取文件名
const paperSlug = PAPER_FILE.split('/').pop().replace('.pdf', '')

const writeResult = await agent(`
你是 LLM Wiki 的维护 agent。请将以下论文报告写入 wiki 并更新知识网络。

## 任务

1. 将完整报告写入 \`wiki/sources/${paperSlug}.md\`
2. 从报告中提取关键实体和概念，在 \`wiki/entities/\` 和 \`wiki/concepts/\` 下创建/更新页面
3. 更新 \`wiki/index.md\` 的索引
4. 追加 \`wiki/log.md\` 的操作记录

## 6-Section 完整报告

以下是论文报告的 6 个 section，请组装为完整的来源报告：

---
# ${TITLE}

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
---

## 报告格式要求

来源报告 frontmatter:
\`\`\`yaml
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
\`\`\`

## 知识提取要求

从报告中提取以下信息，并在报告末尾添加"提取的实体与概念"小节：
- **实体**（方法名、模型名、数据集名等）：每个实体在 wiki/entities/ 下检查是否已有页面，有则更新，无则新建
- **概念**（理论框架、技术范式等）：同上，在 wiki/concepts/ 下管理

实体页面模板（如果新建）：
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
[一段话定义]

## 关键信息
- [核心事实]

## 关系
- [相关实体/概念，带 wiki-link]

## 引用来源
- [[wiki/sources/${paperSlug}]]
\`\`\`

概念页面模板类似，使用 tags: [concept]。

## 索引和日志更新

- 在 wiki/index.md 中更新所有新增/修改的页面条目
- 在 wiki/log.md 末尾追加操作记录

## 完成后

请返回一段简短的操作摘要（≤300 字），列出：
- 报告写入的文件名
- 新建/更新了哪些页面
- 报告评分
`, { label: 'wiki-writer' })

// ===== 只返回摘要给主会话 =====
return {
  summary: writeResult || '报告已写入 wiki',
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

- System Prompt: 学术化中文、具体数字/公式/方法名、设计动机、实质性对比
- Section 1: ≥200 字，领域背景 + 现有痛点 + 研究主张
- Section 2: ≥300 字，架构 + 创新点 + 公式 + 设计动机
- Section 3: ≥200 字，数据集 + 基线 + 关键数字 + 消融分析
- Section 4: ≥200 字，KB 对比 + 论文自述相关工作
- Section 5: ≥150 字，作者局限 + 分析者视角问题 + 改进方向
- Section 6: ≥150 字，贡献定位 + 可迁移性 + 研究启发 + 评分

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

| 优先级 | 类别 | 特征 | 示例 |
|--------|------|------|------|
| 🔴 先处理 | 框架/理论/分类法 | 提出新分类体系、理论框架、全面基准 | KScope, ConflictBank |
| 🟡 中间 | 方法/特定场景 | 解决特定冲突类型的系统/方法 | ConflictRAG, MAGIC |
| 🟢 最后 | 领域外围/弱相关 | 侧重点不在核心主题，在特定领域应用 | FinNLI, FinanceReasoning |

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

本 skill 是 LLM Wiki 框架中"论文"类型来源的专用 Ingest 通道。它遵循 CLAUDE.md 中定义的所有 wiki 规范（页面格式、frontmatter、链接规范、lint 规则等），只是在"来源消化"环节使用了更深度的结构化分析。

当用户同时使用本 skill 和通用 ingest 时（例如一篇论文 + 一篇博客），所有输出统一存储在 `wiki/` 下，共享同一套索引、日志和知识网络。

---

# 注意事项

- **默认轻量模式**：论文原文不进主会话，所有重活（读取、分析、写入）在 Workflow 内部完成。主会话只做调度和汇报
- Skill 只处理论文 PDF。对于非论文内容（文章、博客、书籍笔记），使用 CLAUDE.md 中定义的通用 Ingest 工作流
- **PDF 文本提取**：使用 `pdftotext -layout` 而非 Read 工具（后者会以图片形式加载，消耗大量上下文）
- 如果论文过长导致文本文件 >200KB，在 `pdftotext` 后用 `head` 截断（保留引言到结论部分，去掉参考文献列表的冗余行）
- 如果 Workflow 工具不可用，退回串行模式（6 次独立 agent 调用，Section 6 在最后执行）。串行模式下论文原文会进入主会话，仅适合单篇处理
- 所有输出文件使用相对路径（从 vault 根目录）
- 知识提取环节不要贪多——只提取论文中真正核心且有 wiki 价值的实体和概念

### 批量模式额外注意事项

- **已处理检测只依赖文件名匹配**：如果论文标题相同但 PDF 文件名不同，需手动判断
- **排序不是绝对的**：如果用户有明确的处理顺序偏好，以用户指定为准
- **递进式 KB 刷新是质量关键**：每篇处理完后务必刷新，否则后面的论文 Section 4 会缺少上下文
- **中途中断可恢复**：已处理的论文报告已写入磁盘，恢复时只需处理剩余论文
- **单次批量建议不超过 15 篇**：超出后 KB 上下文过长，且主会话可能超时
