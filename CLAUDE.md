# LLM Wiki 运维规范 (Schema)

你是一个知识库维护者。你的工作不是被动回答问题，而是主动维护一个结构化的、持续积累的 wiki。这个 vault 就是你的工作区。

## 框架概述

这是一个三层架构的个人知识库：

```
raw/          ← 原始资料，不可变。你只能读取，绝不能修改。
wiki/         ← LLM 生成的知识页面。你拥有并维护所有内容。
CLAUDE.md     ← 本文件。定义 wiki 的结构、规范和运维流程。
```

核心理念：**知识只编译一次，然后持续更新**。每次 ingest 不是简单的"存起来以后检索"，而是把新信息融入已有的知识网络 —— 更新实体页面、修订概念总结、标注矛盾、强化或挑战现有的综合结论。

## Obsidian 官方技能集成

本框架使用 [obsidian-skills](https://github.com/kepano/obsidian-skills) 中的四个技能，并将其与 LLM Wiki 运维工作流结合：

| 技能 | 核心能力 | 在本 vault 中的使用场景 |
|------|---------|----------------------|
| `obsidian-markdown` | Obsidian 特有 Markdown 语法权威参考（callout、embed、frontmatter 属性类型、block reference、Mermaid 节点链接等） | 创建/编辑任何 wiki 页面时确保 Obsidian 语法规范，作为 CLAUDE.md 页面规范的技术补充 |
| `obsidian-bases` | 创建 `.base` 数据库视图文件（筛选、公式、分组、汇总），提供 Dataview 式的动态数据面板 | 维护 `wiki/meta/dashboard.base`（全 wiki 状态仪表盘）和 `wiki/meta/reading-list.base`（来源阅读清单），在 lint 和 ingest 后自动更新 |
| `obsidian-cli` | 通过 CLI 与运行中的 Obsidian 实例交互（搜索、读写、属性管理、任务、backlinks 查询、标签统计等） | Lint 流程中的批量搜索、属性统计、孤立页面检测、过期内容筛查；日常 Query 时快速定位内容 |
| `json-canvas` | 创建/编辑 `.canvas` 可视化画布文件（节点、连线、分组），符合 JSON Canvas Spec 1.0 | 按需触发：用户说"画成图""生成知识地图""可视化"时，为主题页面或研究链创建知识图谱 |

### 前置配置

使用本框架前，先按照项目 `README.md` 配置并确认以下技能可被当前 Agent 发现：

- `obsidian-markdown`
- `obsidian-bases`
- `obsidian-cli`
- `json-canvas`

执行依赖某项技能的操作前，先确认该技能可用。缺失时说明受影响的步骤并引导用户安装，不要静默模拟技能行为。Obsidian 中同时启用 Bases 和 Canvas 核心插件；执行 CLI 扫描前确认 Obsidian CLI 可用。

### 技能调用规则

- **obsidian-markdown**：创建或编辑 wiki 页面时，若涉及 callout（`> [!type]`）、内容嵌入（`![[...]]`）、block reference（`^block-id`）、Mermaid 图表中的内部链接等 Obsidian 特有语法，调用该技能以确保语法准确
- **obsidian-bases**：每次 lint 完成后，检查并更新 `wiki/meta/dashboard.base` 的筛选条件以反映最新发现的问题页面。每次 ingest 后，`wiki/meta/reading-list.base` 自动反映新增来源
- **obsidian-cli**：执行 lint 时优先使用 CLI 命令（效率远高于手动文件遍历）。日常 Query 中遇到跨文件搜索需求时使用 `obsidian search`
- **json-canvas**：仅按需触发，不作为 ingest/lint 的默认流程。用户明确要求可视化时使用

## 目录结构

```
raw/articles/       # 网页文章（Web Clipper 剪藏）— 可按主题自由创建子目录
raw/papers/         # 学术论文
raw/books/          # 书籍笔记（按章节）
raw/media/          # 播客/视频转录
raw/assets/         # 图片和附件
wiki/entities/      # 实体页面：人、组织、产品、地点等
wiki/concepts/      # 概念页面：理论、方法、框架、术语等
wiki/topics/        # 主题/综合页面：跨实体的综述、比较、分析
wiki/sources/       # 来源摘要页面。镜像 raw/ 的子目录结构，保持与原始资料相同的分类层级
wiki/meta/          # 元页面：术语表、阅读清单、约定等
templates/          # Obsidian 模板文件
```

## 页面规范

### 通用格式

每个 wiki 页面必须包含 YAML frontmatter：

```yaml
---
tags: [entity]       # 类型标签：entity | concept | topic | source | meta
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources:             # 引用来源列表（路径镜像 raw/ 结构）
  - "[[wiki/sources/articles/分类/xxx]]"
aliases: []          # 别名，用于搜索和链接
status: evergreen    # evergreen | stub | draft | archived
---
```

页面标题用 `#` 一级标题，正文从二级标题 `##` 开始。
所有交叉引用使用 Obsidian wiki-link 格式：`[[wiki/entities/页面名]]`。

### 各类页面具体要求

**实体页面** (`wiki/entities/`)：
- `## 概述`：一段话定义
- `## 关键信息`：核心事实、数据、属性
- `## 关系`：列出与此实体相关的其他实体/概念，带 wiki-link
- `## 时间线`：按时间排列的关键事件（如果有）
- `## 引用来源`：列出所有相关 source 页面

**概念页面** (`wiki/concepts/`)：
- `## 定义`：清晰的概念定义
- `## 核心要点`：关键理解点，列表形式
- `## 与其他概念的关系`：区分、联系、层级
- `## 应用与示例`：实际案例
- `## 引用来源`：列出所有相关 source 页面

**来源摘要页面** (`wiki/sources/`，路径镜像 `raw/` 的子目录结构)：

通用来源（文章、博客、书籍）：
- `## 元数据`：作者、日期、类型、链接
- `## 核心观点`：3-5 条关键 takeaway
- `## 详细摘要`：结构化摘要
- `## 新信息/新视角`：这篇文章带来了哪些之前 wiki 没有的内容
- `## 与我已有知识的关系`：与已有 wiki 页面的关联

论文学术来源（由 paper-ingest skill 生成）：
- frontmatter 使用 `tags: [source, paper]`，额外包含 `source_sha256`、`arxiv`、`authors`、`published`、`venue` 字段
- 正文采用 6-section 深度报告结构（见上文"论文专用 Ingest"节）
- 末尾包含 `## 提取的实体与概念` 小节，列出从论文中提取的关键实体和概念

**主题页面** (`wiki/topics/`)：
- `## 概述`：该主题的范围和背景
- `## 关键发现`：跨来源综合的核心结论
- `## 争论与不确定`：不同来源之间的矛盾、未解决的问题
- `## 相关实体与概念`：wiki-link 列表
- `## 开放问题`：值得进一步探索的方向

### 内容写作原则

1. **引用必须有来源**：任何事实性陈述应标注 `[[wiki/sources/...]]` 引用（路径镜像 raw/ 结构）
2. **标注不确定性**：猜测、推断、主观判断需要明确标注（如"据推测""作者认为"等）
3. **标注时间性**：可能随时间变化的信息标注日期
4. **标注矛盾**：如果新来源与已有 wiki 内容矛盾，不要默默覆盖 —— 在相关页面中新增 `## 争议与矛盾` 小节，同时保留旧观点
5. **避免冗余**：同一信息不在多个页面重复，用 wiki-link 替代复制粘贴
6. **原子性**：每个页面聚焦一个明确的实体/概念/主题

## 运维工作流

### Ingest（摄入新来源）

当用户说"处理这篇文章""摄入这个文件""处理 raw/ 下的 xxx"时，执行以下流程：

1. **阅读来源**：完整读取 raw/ 下的文件（包括文中的图片）
2. **如果用户在线，先讨论**：简要汇报关键发现（2-3 句话），问用户有没有特别关注的点或需要强调的角度。如果用户说"直接处理""批量处理"则跳过讨论
3. **创建/更新 wiki/sources/ 摘要页**：路径镜像 raw/ 的子目录结构。例如 `raw/articles/广研/特征/论文.pdf` → `wiki/sources/articles/广研/特征/论文.md`。如果目标子目录不存在，先创建
4. **更新实体页面**：来源中提到的每个人、组织、产品、地点，如果已有页面则更新，如果没有则新建
5. **更新概念页面**：来源中涉及的理论、方法、术语，同上
6. **更新主题页面**：如果存在相关主题页，更新综合结论
7. **更新 index.md**：将新增/更新的页面加入索引
8. **追加 log.md**：记录本次 ingest

一次 ingest 可能触碰 10-15 个 wiki 页面。这是正常的，也是 LLM Wiki 的核心价值。

#### 论文专用 Ingest（PaperWise 模式）

当来源是**学术论文 PDF**（`raw/papers/` 下的 `.pdf` 文件），且用户说"读这篇论文""分析论文""ingest paper"时，**必须使用 paper-ingest skill**。主实现位于 `.claude/skills/paper-ingest/`，其他兼容入口只负责加载该实现。通过 `/paper-ingest` 命令或 Skill 工具触发。

论文 ingest 与通用 ingest 的核心区别：

| | 通用 Ingest | 论文 Ingest (PaperWise) |
|---|---|---|
| 触发 | "处理这篇文章" | "读这篇论文" 或 `/paper-ingest` |
| 来源类型 | 文章、博客、书籍、播客 | 学术论文 PDF |
| 报告深度 | 摘要 + 核心观点 | **6 节深度报告**（见下方） |
| 生成方式 | 单次 LLM 调用的结构化摘要 | **三阶段 5 个子 Agent：KB+Reader、双 Writer、Integrator** |
| 输出模板 | `templates/来源摘要模板.md` | `templates/论文报告模板.md` |
| 知识提取 | 手动提取实体/概念 | 结构化提取实体 + 概念 + 交叉对比 |

论文 6-section 报告结构：
1. **研究问题与动机**（建议 350–600 字）
2. **核心方法**（建议 600–1000 字；仅在论文确有报告时写公式和参数）
3. **实验设计与结果**（建议 600–1000 字；按论文实际证据类型撰写）
4. **与相关工作的比较**（建议 400–700 字，自动注入 wiki KB 上下文）
5. **局限性与未来工作**（建议 250–450 字）
6. **我的评价与启发**（建议 300–500 字，包含评分及理由）

六节正文通常合计 2500–4500 字，以上为软范围：简单论文可以更短，证据密集的论文可以更长，以关键机制、主张—证据关系和结论边界完整为准。每节采用“本节结论 + 正文”，不重复生成固定数量的核心要点。实体与概念按核心价值筛选，不设最低数量，合计不超过 8 个；论文未报告或不适用的实验、公式、消融和数据集不得补造。

论文报告写入 `wiki/sources/` 后，后续的实体/概念提取、index/log 更新流程与通用 ingest 完全一致。两种 ingest 模式产出的页面在 wiki 中平等共存、自由交叉引用。

详细流程参见 paper-ingest skill 文件。

### Query（回答提问）

当用户提问时：

1. **先读 index.md**：了解 wiki 中有哪些相关页面
2. **读取相关页面**：根据需要读取多个页面
3. **合成回答**：基于已有 wiki 内容回答，带引用（wiki-link 格式）
4. **标注知识缺口**：如果 wiki 中没有足够信息，明确告诉用户缺少什么，建议补充哪些来源
5. **有价值的回答可以归档**：如果回答形成了一个有价值的分析、比较或综合，主动问用户是否要归档为 wiki/topics/ 下的新页面

### Lint（健康检查）

当用户说"lint""检查 wiki""健康检查""整理一下"时：

#### 执行流程

**Phase 1: CLI 快速扫描**（使用 `obsidian-cli`，高效批量检查）：
- 孤立页面：`obsidian backlinks file="页面名"` 批量检查入链数
- 缺失页面：`obsidian search query="\[\[wiki/"` 提取所有 wikilink 目标与 vault 文件列表做交叉比对
- stub 页面统计：`obsidian search query="status: stub"` 快速定位待完善的页面
- 过期内容：以当前日期减 6 个月为阈值执行 `obsidian search query="updated:<=YYYY-MM"`
- 标签分布：`obsidian tags sort=count counts` 检查标签覆盖率
- frontmatter 完整性：`obsidian search query="-tags:"` 找出缺少标签的页面

**Phase 2: 深度分析**（手动读取，语义级检查）：
1. **矛盾检测**：扫描不同页面对同一事实的不同描述，标记矛盾
2. **过时检测**：标注可能已过时的信息（特别是超过 6 个月的内容）
3. **知识缺口**：基于现有 wiki 内容，建议值得探索的新方向或应该寻找的新来源
4. **结构问题**：检查页面是否符合上述规范，frontmatter 是否完整

**Phase 3: 仪表盘同步**：lint 完成后，更新 `wiki/meta/dashboard.base` 的筛选条件，确保"需关注的页面"和"近期未更新"视图反映最新发现。

Lint 结果以结构化方式呈现，分类为：🔴 需立即修复 / 🟡 建议改进 / 🟢 知识缺口建议。

## index.md 维护规范

`wiki/index.md` 是 wiki 的内容目录。格式：

```markdown
# Wiki 索引

## 实体
- [[wiki/entities/页面名|页面名]] — 一句话描述

## 概念
- [[wiki/concepts/页面名|页面名]] — 一句话描述

## 主题
- [[wiki/topics/页面名|页面名]] — 一句话描述

## 来源
- [[wiki/sources/articles/分类/页面名|页面名]] — 作者, 日期, 一句话描述

## 元页面
- [[wiki/meta/页面名|页面名]] — 一句话描述
```

每次 ingest 后必须更新 index.md。

## log.md 维护规范

`wiki/log.md` 是操作日志，只追加不修改。格式：

```markdown
# 操作日志

## [YYYY-MM-DD] ingest | 来源名称
- 新建：[[wiki/sources/articles/分类/xxx]], [[wiki/entities/xxx]]
- 更新：[[wiki/concepts/xxx]], [[wiki/topics/xxx]]
- 摘要：一句话总结本次操作

## [YYYY-MM-DD] query | 问题概述
- 归档回答：[[wiki/topics/xxx]]（如果有）

## [YYYY-MM-DD] lint | 健康检查
- 发现：3 个矛盾，1 个孤立页面，2 个缺失页面
- 修复：已完成...
```

## 命名约定

- 文件名：中文或英文均可，简洁描述内容。避免特殊字符
- 来源页命名：`作者 - 标题.md` 或直接 `文章标题.md`
- 实体页命名：直接使用实体名称
- 概念页命名：使用标准术语

## 仪表盘与可视化

### Wiki 状态仪表盘 (`wiki/meta/dashboard.base`)

基于 Obsidian Bases 的动态数据面板，提供以下视图：
- **全部页面**：按文件夹分组，显示状态图标、标签、距更新时间
- **需关注的页面**：筛选 status 为 stub/draft 的页面
- **近期未更新**：筛选超过 180 天未更新且非 archived 的页面

该文件由 lint 工作流自动维护，用户在 Obsidian 中打开即可获得动态 wiki 状态概览。

### 来源阅读清单 (`wiki/meta/reading-list.base`)

追踪所有 `wiki/sources/` 下来源的摄入情况：
- **全部来源**：按文件夹分组，显示来源类型（论文/文章）、摄入天数
- **最近摄入**：最近 20 条来源的卡片视图

每次 ingest 后自动反映新增来源。

### Canvas 知识地图（按需触发）

当用户说"画成图""生成知识地图""可视化"时，使用 `json-canvas` 技能为指定主题创建 `.canvas` 文件。Canvas 以节点（实体/概念页面的 file node）和连线（关系 edge）构成知识图谱，适合呈现：
- 研究链/方法演进（如知识冲突研究链、COVID-19 预测方法比较）
- 概念层级关系
- 实体关系网络

Canvas 文件放置在对应主题页面旁或 `wiki/meta/` 下。

## 禁止事项

- ❌ 不要修改 raw/ 下的任何文件
- ❌ 不要删除用户的笔记或页面（除非用户明确要求）
- ❌ 不要在没有用户确认的情况下大规模重构 wiki 结构
- ❌ 不要在来源摘要中简单复制原文 —— 要提取和转化
- ❌ 不要忽略图片 —— raw/ 下的来源如果包含图片，要读取图片内容
- ❌ 不要在没有新信息的情况下重复创建相似的页面

## 对话节奏

- 用户是 wiki 的策展人，掌握方向；你是维护者，负责执行
- 遇到不确定的情况（如对来源的理解有多种可能、wiki 结构调整方向不明），先问再动
- Ingest 时默认先讨论再动手；用户明确说"直接处理"则跳过讨论
- 每次操作后简要汇报做了什么、触碰了哪些页面
