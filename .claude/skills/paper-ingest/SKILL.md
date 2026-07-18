---
name: paper-ingest
description: 深度阅读单篇或批量学术论文 PDF，生成六节结构化报告并融入 Obsidian LLM Wiki。用于用户要求读论文、分析论文、处理论文 PDF 或批量摄入论文目录时。
---

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

**核心设计**：论文全文只被读取一次（Phase 1 reader agent），产出一份结构化提取稿，所有下游 agent 共享。主会话完全不接触论文内容、KB 搜索和 wiki 文件。

```
主会话 (真正的轻量)              Workflow 内部
──────────────────              ──────────────
Step 0: pdftotext 提取          Phase 0+1 并行: KB构建 | 论文阅读+结构化提取
Step 1: 启动 Workflow ────────▶ Phase 2: 双agent并行写作 (S1-3 | S4-6+存在性检查)
                                Phase 3: wiki一体化落地 (写报告+实体+概念+index+log)
Step 2: 接收 ~200字摘要 ◀────  返回摘要
```

**核心原则**：
- 论文全文（50-150KB）**不进主会话**，仅在 Workflow Phase 1 读取 **1 次**
- 所有 wiki 文件读写均在 Workflow 内部完成，主会话不接触
- 主会话只拿到 ≤200 字摘要，多篇连续处理时主上下文不膨胀
- 内容组织遵循“低冗余、高关联”：报告聚焦一篇论文，实体/概念页面聚焦单一对象，跨页面关系使用 wiki-link 而不是复制正文
- Agent 之间遵循“高内聚、低耦合”：各自只完成一个明确阶段，通过结构化结果传递，失败不向下游扩散
- Phase 0（KB 构建）和 Phase 1（论文提取）并行执行，减少 wall-clock
- Phase 2 由 2 个 agent 共享同一份提取稿，并行撰写两组章节

---

## 主会话流程

1. 确认用户指定的单篇 PDF；未指定时列出候选文件。
2. 使用 `bash .claude/skills/paper-ingest/scripts/prepare_pdf.sh "论文路径.pdf"` 执行确定性预检；主会话只读取脚本返回的短状态清单。
3. `PDF_STATUS: FAILED` 或 `NEEDS_OCR` 时停止，不启动 Workflow。`PDF_STATUS: OK` 时从 `TEXT_PATH` 取得论文文本路径，并保留 `PDF_SHA256`。
4. 从 raw 相对路径计算报告目标路径，执行 `bash .claude/skills/paper-ingest/scripts/check_ingest_state.sh "PDF_SHA256" "报告目标路径"`。
5. `INGEST_STATE: UNCHANGED` 时直接返回已有报告路径，不启动 Workflow；`NEW`、`LEGACY` 或 `CHANGED` 时继续。
6. 从文件名推断标题，构造 `paperPath`、`paperFile`、`paperMeta`、`vaultRoot`、`title`、`today` 和可选 `batchContext`。
7. 调用下方 Workflow；论文正文、KB、提取稿和 wiki 内容均停留在 Workflow 内部。
8. 只接收 `status`、可选的 `errorType`、不超过 200 字的 `summary` 和 `reportFile`；`errorType` 用于区分 Agent 明确失败和输出协议错误。

批量请求才读取 [references/batch-mode.md](references/batch-mode.md)；单篇处理不要读取。

---

## Workflow 脚本模板

### 架构总览

```
Phase 0+1 并行:
  Agent KB:  搜索 wiki 相关论文 → KB 上下文 (≤1600字)
  Agent Read: 读取论文全文 → 结构化提取稿 (通常5-8KB，复杂论文≤10KB) + 实体清单 + 概念清单

Phase 2 并行:
  Agent A: 读提取稿 → 撰写 Section 1-3（论文内部：问题/方法/实验）
  Agent B: 读提取稿+KB上下文 → 撰写 Section 4-6（论文外部：比较/局限/评价）
           + 检查实体/概念在 wiki 中的存在性

Phase 3:
  Agent Integrate: 组装报告 → 写入 wiki/sources/
                   → 创建/更新实体页面
                   → 创建/更新概念页面
                   → 更新 index.md + log.md
                   → 返回 ≤200字摘要
```

### 脚本

```javascript
export const meta = {
  name: 'paper-ingest',
  description: 'Read the paper once, write two section groups in parallel, then integrate the report and wiki updates.',
  phases: [
    { title: 'Prepare', detail: 'KB context + paper structured extraction (parallel)' },
    { title: 'Write', detail: '2 agents parallel: sections 1-3 | sections 4-6 + existence check' },
    { title: 'Integrate', detail: 'Write report + entities + concepts + update index/log' },
  ],
}

function extractStructured(raw, marker) {
  if (!raw) return { status: '', text: '' }
  const match = raw.match(new RegExp(`^${marker}:[ \\t]*(OK|FAILED)[ \\t]*\\r?$`, 'm'))
  if (!match) return { status: '', text: '' }
  const text = raw.slice(match.index).trim().replace(/\n```[ \\t]*$/, '').trim()
  return { status: match[1], text }
}

if (
  extractStructured('prefix\nEXTRACTION_STATUS: OK\nbody', 'EXTRACTION_STATUS').status !== 'OK' ||
  extractStructured('```text\nINTEGRATION_STATUS: OK\n```', 'INTEGRATION_STATUS').text !== 'INTEGRATION_STATUS: OK' ||
  extractStructured('INTEGRATION_STATUS: FAILED', 'INTEGRATION_STATUS').status !== 'FAILED' ||
  extractStructured('expected EXTRACTION_STATUS: OK', 'EXTRACTION_STATUS').status !== '' ||
  extractStructured('no status', 'EXTRACTION_STATUS').status !== ''
) {
  throw new Error('paper-ingest status parser self-check failed')
}

// ===== 参数 =====
const PAPER_PATH = args.paperPath
const PAPER_FILE = args.paperFile
const VAULT_ROOT = args.vaultRoot
const TITLE = args.title
const TODAY = args.today
const PAPER_META = args.paperMeta || ''
const BATCH_CTX = args.batchContext || ''
const CONTRACT_ROOT = VAULT_ROOT + '/.claude/skills/paper-ingest/references'
const READER_CONTRACT = CONTRACT_ROOT + '/reader-contract.md'
const WRITER_CONTRACT = CONTRACT_ROOT + '/writer-contract.md'
const INTEGRATOR_CONTRACT = CONTRACT_ROOT + '/integrator-contract.md'

const sourceRelative = PAPER_FILE.replace(VAULT_ROOT + '/raw/', '').replace(/\.pdf$/, '')
const sourceDir = sourceRelative.includes('/') ? sourceRelative.substring(0, sourceRelative.lastIndexOf('/')) : ''

// ===== Phase 0+1: KB构建 与 论文提取 并行 =====
phase('Prepare')

const [kbContextRaw, extractionRawResult] = await parallel([
  // Agent KB: 构建知识库上下文
  () => agent(`你是 LLM Wiki 的检索 agent。为即将分析的论文构建知识库上下文，供 Section 4（与相关工作的比较）使用。

## 任务
1. 读取 \`${VAULT_ROOT}/wiki/index.md\`，在「来源」分类下找到与论文《${TITLE}》主题相关的已有论文报告
2. 对于匹配到的论文报告（最多 5 篇），先只读取其 frontmatter 和快速预览表（前 30 行）完成相关性排序
3. 选取最相关的 2 篇；仅继续读取其第 2 节核心方法、第 3 节实验设计与结果和第 5 节局限性与未来工作，不读取其他正文
4. 按以下格式输出（总长度 ≤1600 字）：

\`\`\`
## 知识库上下文（已读论文，用于 Section 4 对比）

- **[[wiki/sources/path/文件名|论文标题]]** (年份, 期刊/会议) 评分: X/10
  核心方法: [与当前论文相关的方法机制]
  关键证据: [主要结果及其证据基础]
  主要局限: [影响比较结论的边界]
  可比维度: [当前论文可与其比较的具体维度]
\`\`\`

5. 只有 1 篇相关报告时只读取 1 篇；没有相关报告时输出一行：\`KB_EMPTY\`
6. 直接返回 KB 上下文文本，不写临时文件

${BATCH_CTX ? '## 批量上下文（本批次已处理的论文）\n' + BATCH_CTX + '\n请将以上批量上下文也纳入 KB 上下文。' : ''}

只返回 KB 上下文文本或 KB_EMPTY。不要额外解释。`, { label: 'kb-context' }),

  // Agent Read: 论文全文阅读 + 结构化提取
  () => agent(`先使用 Read 读取 \`${READER_CONTRACT}\` 并严格执行其中契约。

## 动态输入
- 论文文本：\`${PAPER_PATH}\`
- 原始 PDF：\`${PAPER_FILE}\`
- PDF 预检清单：
${PAPER_META}
- 文件名推断标题：${TITLE}

读取契约后完整读取论文文本，只返回契约规定的结构化提取稿。`, { label: 'reader' }),
])

const extraction = extractStructured(extractionRawResult, 'EXTRACTION_STATUS')

if (!extraction.status) {
  return {
    status: 'needs_attention',
    errorType: 'reader_protocol_error',
    summary: 'Reader 输出协议错误：未找到合法的 EXTRACTION_STATUS 状态行，未写入 wiki。',
    reportFile: '',
  }
}

if (extraction.status === 'FAILED') {
  return {
    status: 'needs_attention',
    errorType: 'reader_failed',
    summary: 'Reader 明确返回提取失败，未写入 wiki。请检查其 FAILURE_REASON。',
    reportFile: '',
  }
}

const extractionRaw = extraction.text

// ===== Phase 2: 双 agent 并行写作 =====
phase('Write')

const [sectionsInternal, sectionsExternal] = await parallel([
  // Agent A: Section 1-3（论文内部视角）
  () => agent(`先使用 Read 读取 \`${WRITER_CONTRACT}\` 并严格执行其中契约。

## 任务
只撰写第 1–3 节，不读取论文原文，不写入 wiki。

## 论文标题
${TITLE}

## 结构化提取稿
${extractionRaw}

只返回契约规定的三个章节。`, { label: 'sections-1-3' }),

  // Agent B: Section 4-6（论文外部视角）+ 存在性检查
  () => agent(`先使用 Read 读取 \`${WRITER_CONTRACT}\` 并严格执行其中契约。

## 任务
只撰写第 4–6 节并输出存在性 JSON，不读取论文原文，不写入 wiki。

## 论文标题
${TITLE}

## 结构化提取稿
${extractionRaw}

## KB 上下文
${kbContextRaw || 'KB_EMPTY'}

## Vault 根目录
${VAULT_ROOT}

只返回契约规定的三个章节、分隔线和 JSON。`, { label: 'sections-4-6' }),
])

const requiredInternalSections = [
  '## 1. 研究问题与动机',
  '## 2. 核心方法',
  '## 3. 实验设计与结果',
]
const requiredExternalSections = [
  '## 4. 与相关工作的比较',
  '## 5. 局限性与未来工作',
  '## 6. 我的评价与启发',
  '---EXISTENCE---',
]

if (
  !sectionsInternal ||
  !sectionsExternal ||
  !requiredInternalSections.every((heading) => sectionsInternal.includes(heading)) ||
  !requiredExternalSections.every((heading) => sectionsExternal.includes(heading))
) {
  return {
    status: 'needs_attention',
    summary: '报告章节生成不完整，未写入 wiki。请检查 Workflow writer 输出。',
    reportFile: '',
  }
}

// ===== Phase 3: Wiki 一体化落地 =====
phase('Integrate')

const finalSummaryRaw = await agent(`先使用 Read 读取 \`${INTEGRATOR_CONTRACT}\` 并严格执行其中契约。

## 动态输入
- 论文标题：${TITLE}
- 原始 PDF：${PAPER_FILE}
- PDF 预检清单：
${PAPER_META}
- Vault 根目录：${VAULT_ROOT}
- 日期：${TODAY}
- raw 相对路径（无扩展名）：${sourceRelative}
- 报告目录：${sourceDir}
- 报告目标路径：${VAULT_ROOT}/wiki/sources/${sourceRelative}.md

## 结构化提取稿
${extractionRaw}

## 第 1–3 节
${sectionsInternal}

## 第 4–6 节与存在性 JSON
${sectionsExternal}

所有 wiki 读写均在本 Agent 内完成。只返回契约规定的集成状态和短摘要。`, { label: 'wiki-integrate' })

const integration = extractStructured(finalSummaryRaw, 'INTEGRATION_STATUS')

if (!integration.status) {
  return {
    status: 'needs_attention',
    errorType: 'integration_protocol_error',
    summary: 'Integrator 输出协议错误：未找到合法的 INTEGRATION_STATUS 状态行。可能存在部分写入，请先核对报告路径。',
    reportFile: 'wiki/sources/' + sourceRelative + '.md',
  }
}

if (integration.status === 'FAILED') {
  return {
    status: 'needs_attention',
    errorType: 'integration_failed',
    summary: 'Integrator 明确返回集成失败。可能存在部分写入，请检查其失败原因和报告路径。',
    reportFile: 'wiki/sources/' + sourceRelative + '.md',
  }
}

const finalSummary = integration.text

// ===== 返回摘要给主会话 =====
return {
  status: 'success',
  summary: finalSummary.slice(0, 200),
  reportFile: 'wiki/sources/' + sourceRelative + '.md',
}
```

---

## Step 2: 主会话收尾（轻量）

Workflow 完成后，主会话接收 ≤200 字的操作摘要。向用户汇报：

- `CREATED` 或 `UPDATED`：报告 wiki-link、评分和一句话评价、新建或更新了哪些页面，以及值得注意的发现。
- `SKIPPED_UNCHANGED`：只报告既有报告 wiki-link 和未执行写入，不使用本轮 Writer 生成的评分。
- `needs_attention`：结合 `errorType` 明确说明是 Agent 返回失败还是输出协议错误；集成阶段异常时不得仅凭报告文件存在就声称全部摄入成功。

---

# 批量处理模式

用户明确要求批量处理时，主会话读取 [references/batch-mode.md](references/batch-mode.md)，按其中规则扫描、排序和逐篇调用同一 Workflow。单篇请求不加载该文件。

---

# 与 LLM Wiki 框架的关系

本 skill 是 LLM Wiki 框架中"论文"类型来源的专用 Ingest 通道。遵循 CLAUDE.md 中定义的所有 wiki 规范（页面格式、frontmatter、链接规范、lint 规则等）。

当用户同时使用本 skill 和通用 ingest 时，所有输出统一存储在 `wiki/` 下，共享同一套索引、日志和知识网络。

---

# 注意事项

- Skill 只处理论文 PDF；其他来源使用 `CLAUDE.md` 中的通用 Ingest。
- 主会话只执行 `scripts/prepare_pdf.sh`、Workflow 调用和短摘要转述，不读取论文正文或 wiki。
- Reader、Writer、Integrator 分别读取自己的 reference；不要把 reference 内容复制回主提示。
- 任一阶段返回失败状态时立即停止，不启动下游阶段。
- 实体和概念不设最低数量，合计不超过 8 个。
- Workflow 不可用时再退回主会话串行模式，并明确提醒上下文会显著增加。
