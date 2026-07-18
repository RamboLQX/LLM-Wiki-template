# 已有 LLM Wiki 更新指南

本指南用于把模板中的框架规则、页面模板、paper-ingest skill 和仪表盘合并到已经投入使用的 Vault。更新必须采用比较与合并方式，不能直接覆盖整个目录。

## 框架变化

- 来源报告路径镜像 `raw/` 的目录结构。
- 论文报告记录 PDF SHA-256，避免未变化来源重复摄入。
- Paper ingest 使用一份主实现和一个 Codex 兼容入口，并按需加载 Agent 契约、批量规则和预检脚本。
- Lint 由 CLI 快速扫描、语义分析和仪表盘同步组成。
- 增加 Wiki 状态仪表盘、来源阅读清单和按需 Canvas 可视化。
- 框架使用 `obsidian-markdown`、`obsidian-bases`、`obsidian-cli` 和 `json-canvas`。

## 受保护内容

更新时不得删除、覆盖或移动：

- `raw/**`
- `wiki/entities/**`
- `wiki/concepts/**`
- `wiki/topics/**`
- `wiki/sources/**`
- `wiki/index.md`
- `wiki/log.md`
- 用户自建的项目、笔记、模板和 meta 页面
- `.claude/settings.json` 及其他本地权限配置
- `.claudian/**`、Obsidian 工作区状态、插件文件和会话数据

## 交给 Agent 的提示词

```text
你正在升级一个已经投入使用的 LLM Wiki Vault。

现有 Vault：
<填写用户现有 Wiki 的绝对路径>

新版模板：
<填写新版 LLM-Wiki-template 的绝对路径>

目标：
将新版模板中的 Agent 规则、页面模板、paper-ingest skill 和 Bases 仪表盘合并到现有 Vault，同时完整保留用户已经摄入和整理的知识内容。

必须遵守以下规则：

1. 第一阶段只读检查，不立即修改。
2. 先读取新版模板中的 UPGRADE.md、AGENTS.md、CLAUDE.md、README.md。
3. 检查 obsidian-markdown、obsidian-bases、obsidian-cli、json-canvas 是否可被当前 Agent 发现。缺失时先说明安装方法和受影响步骤，不要静默模拟技能行为。
4. 比较以下框架文件：
   - AGENTS.md
   - CLAUDE.md
   - templates/
   - .claude/skills/paper-ingest/
   - .agents/skills/paper-ingest/
   - wiki/meta/论文处理约定.md
   - wiki/meta/dashboard.base
   - wiki/meta/reading-list.base
5. 严禁删除、覆盖、移动或批量改写：
   - raw/**
   - wiki/entities/**
   - wiki/concepts/**
   - wiki/topics/**
   - wiki/sources/**
   - wiki/index.md
   - wiki/log.md
   - 用户自建的项目、笔记、模板和 meta 页面
6. 不复制新版模板或现有 Vault 中的本地状态：
   - .claudian/**
   - .obsidian/workspace*.json
   - .obsidian/plugins/**
   - .claude/settings.json
   - 会话、缓存、锁文件和密钥
7. AGENTS.md、CLAUDE.md 和用户自定义模板必须采用合并方式：
   - 保留用户已有的自定义规则；
   - 加入新版缺失章节；
   - 如果存在冲突，列出冲突并等待用户决定，不得直接覆盖。
8. paper-ingest 属于框架维护目录，可以在用户确认后升级：
   - .claude/skills/paper-ingest/ 作为唯一完整实现；
   - .agents/skills/paper-ingest/SKILL.md 作为兼容入口；
   - 不保留两份彼此独立的实现。
9. 如果现有 Vault 是 Git 仓库，修改前检查 git status；工作区存在未提交修改时不得覆盖相关文件。
10. 修改前先输出：
   - 模板带来的功能变化；
   - 将新增、修改、保留的文件；
   - 发现的用户自定义内容；
   - 潜在冲突；
   - 验证方案。
11. 等待用户明确确认后再执行修改。

完成修改后验证：

- raw 和已有 wiki 内容的文件数量及路径未发生变化；
- wiki/index.md 和 wiki/log.md 未被模板内容覆盖；
- paper-ingest skill frontmatter、引用路径和 shell 脚本有效；
- dashboard.base 和 reading-list.base 是合法 YAML；
- git diff 中没有用户知识内容、本地会话、插件文件、绝对个人路径或密钥；
- 输出最终改动清单和需要用户手动处理的事项。

禁止执行 git clean、git reset --hard、强制 checkout 或任何批量删除命令。
```

## 更新后的最低检查

1. 确认四个 Obsidian skills 可被 Agent 发现。
2. 检查 `AGENTS.md`、`CLAUDE.md` 中的用户自定义规则仍然存在。
3. 检查 paper-ingest 的主实现、references 和 scripts 齐全。
4. 确认 `raw/`、已有 Wiki 页面、索引和日志没有被覆盖。
5. 检查 Git 差异中没有本地会话、插件、绝对个人路径或密钥。
