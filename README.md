# LLM Wiki Template

面向 **Obsidian + Claudian / Claude Code / Codex** 的 AI 知识库模板。

它不是一个把资料存起来再检索的 RAG 项目，而是一个让 AI agent 持续维护 Obsidian 知识网络的工作区：用户把原始资料放进 `raw/`，Claudian 中的 Claude Code / Codex 等 agent 按照 `CLAUDE.md` 或 `AGENTS.md` 的规则，把资料编译成结构化、可交叉引用、可持续更新的 `wiki/` 页面。

## 适合谁

- 用 Obsidian 管理阅读、研究、论文、文章和长期知识的人
- 想让 Claude Code / Codex 直接在 vault 里读写 Markdown 的人
- 不满足于“问一次答一次”，希望 AI 帮自己维护一个会成长的 wiki 的人
- 需要批量消化论文，并沉淀实体、概念、主题和来源摘要的人

## 核心思想

**知识只编译一次，然后持续更新。**

原始资料放在 `raw/` 下，默认只读；AI 生成和维护的知识页面放在 `wiki/` 下。每次 ingest 新资料时，agent 不只是生成一篇孤立摘要，而是会更新已有实体页面、概念页面、主题页面、来源页、索引和操作日志。

## 目录结构

```text
.
├── CLAUDE.md                         # Claude/Claudian 使用的 LLM Wiki 运维规范
├── AGENTS.md                         # Codex 使用的 LLM Wiki 运维规范
├── README.md                         # 给用户看的使用说明
├── .claude/
│   ├── settings.example.json          # Claude/Claudian 权限配置示例
│   └── skills/
│       └── paper-ingest/
│           └── SKILL.md               # 论文深度 ingest skill
├── .agents/
│   └── skills/
│       └── paper-ingest/
│           └── SKILL.md               # Codex 版论文深度 ingest skill
├── raw/                               # 原始资料，只读
│   ├── articles/
│   ├── papers/
│   ├── books/
│   ├── media/
│   └── assets/
├── templates/                         # 来源摘要和论文报告模板
└── wiki/                              # AI 维护的知识网络
    ├── entities/
    ├── concepts/
    ├── topics/
    ├── sources/
    ├── meta/
    ├── index.md
    └── log.md
```

## 快速开始

### 1. 使用这个模板

在 GitHub 上点击 **Use this template**，创建你自己的知识库仓库，然后 clone 到本地。

也可以直接下载本项目，把整个文件夹作为一个新的 Obsidian vault 打开。

### 2. 用 Obsidian 打开 vault

在 Obsidian 中选择：

```text
Open folder as vault
```

然后选择这个项目目录。

### 3. 安装 Claudian

在 Obsidian 的 Community Plugins 中安装并启用 **Claudian**。Claudian 可以把 Claude Code、Codex、Opencode 等 agent 嵌入到 Obsidian vault 中，让 agent 直接读取和编辑当前知识库。

Claudian 项目：

- Obsidian 插件页：https://community.obsidian.md/plugins/realclaudian
- GitHub：https://github.com/YishenTu/claudian

### 4. 配置 Agent 权限

本模板默认不提交 `.claude/settings.json`，因为它属于本地权限配置。

如果你使用 Claude Code / Claudian，可以复制示例配置：

```bash
cp .claude/settings.example.json .claude/settings.json
```

然后根据自己的信任边界调整权限。

如果你使用 Codex，请让 Codex 在项目根目录读取 `AGENTS.md`；论文 ingest skill 位于 `.agents/skills/paper-ingest/SKILL.md`。

### 5. 放入原始资料

把资料放入对应目录：

```text
raw/articles/    # 网页文章、博客、长文
raw/papers/      # 学术论文 PDF
raw/books/       # 书籍笔记或章节
raw/media/       # 播客、视频转录
raw/assets/      # 图片和附件
```

`raw/` 是原始资料区。Agent 应读取它，但不应修改它。

## 基础工作流

### 摄入文章

把文章 Markdown 放入 `raw/articles/`，然后在 Claudian 里对 agent 说：

```text
处理 raw/articles/xxx.md
```

Agent 会按照 `CLAUDE.md` 或 `AGENTS.md` 的通用 ingest 流程：

- 创建或更新 `wiki/sources/` 下的来源摘要
- 提取相关实体到 `wiki/entities/`
- 提取相关概念到 `wiki/concepts/`
- 更新主题页、索引和操作日志

### 摄入论文

把 PDF 放入 `raw/papers/`，然后说：

```text
读这篇论文：raw/papers/xxx.pdf
```

或：

```text
使用 paper-ingest 处理 raw/papers/xxx.pdf
```

论文会走 paper-ingest skill 定义的深度流程，生成 6 节论文报告：

- Claude/Claudian：`.claude/skills/paper-ingest/SKILL.md`
- Codex：`.agents/skills/paper-ingest/SKILL.md`

1. 研究问题与动机
2. 核心方法
3. 实验设计与结果
4. 与相关工作的比较
5. 局限性与未来工作
6. 我的评价与启发

### 查询知识库

当你提问时，agent 会先读 `wiki/index.md`，再读取相关页面，然后基于已有 wiki 内容回答。

示例：

```text
根据现有 wiki，总结一下我们读过的 RAG 冲突检测方法。
```

如果现有 wiki 信息不足，agent 应明确指出缺口，而不是编造答案。

### 健康检查

你可以让 agent 检查知识库状态：

```text
检查 wiki
```

或：

```text
lint
```

它会检查矛盾、过时信息、孤立页面、缺失页面、broken links 和结构问题。

## Paper Ingest 依赖

论文 PDF 解析依赖 `pdftotext`。macOS 用户通常可以通过 poppler 安装：

```bash
brew install poppler
```

为了安全，模板没有默认允许 agent 执行 `brew install`。请你自己在终端安装依赖，再让 agent 运行论文 ingest。

## Git 建议

本模板默认：

- 提交框架、模板、skill 和空目录占位文件
- 不提交用户放入 `raw/` 的原始资料
- 不提交 ingest 后生成的大量 wiki 内容
- 保留 `wiki/index.md` 和 `wiki/log.md` 作为初始模板
- 不提交 `.claude/settings.json` 这类本地权限配置

如果你希望把自己的 wiki 内容也同步到私有仓库，可以按需要调整 `.gitignore`。

## 发布到 GitHub

如果你要把自己的版本发布成模板仓库：

1. 确认没有提交私人资料、论文 PDF、个人笔记或本地权限配置
2. 初始化 Git 仓库并提交
3. 推送到 GitHub
4. 在仓库设置中打开 **Template repository**

示例命令：

```bash
git init
git add .
git commit -m "Initial LLM Wiki template"
git branch -M main
git remote add origin git@github.com:YOUR_NAME/llm-wiki-template.git
git push -u origin main
```

## 常见问题

### 这和普通 Obsidian 模板有什么区别？

普通模板主要规定页面格式；这个项目还规定了 AI agent 的运维流程。`CLAUDE.md` 和 `AGENTS.md` 告诉 agent 如何摄入资料、如何维护索引、如何处理矛盾、如何做健康检查。

### 这和 RAG 有什么区别？

RAG 通常是在查询时临时检索资料；LLM Wiki 更像持续编译。每次处理资料时，AI 都会把新知识融入已有页面，让知识网络长期演化。

### 一定要用 Claudian 吗？

推荐使用 Claudian，因为这个模板的目标场景就是在 Obsidian 内直接调用 agent。你也可以在终端中让 Claude Code / Codex 打开这个 vault 目录执行同样规则。

### 可以把生成的 wiki 内容提交到 GitHub 吗？

可以。如果是公开仓库，请先确认没有隐私内容；如果是个人私有知识库，可以把 `.gitignore` 中的 `wiki/entities/*`、`wiki/concepts/*`、`wiki/topics/*`、`wiki/sources/*` 规则删掉或按需调整。

## License

MIT
