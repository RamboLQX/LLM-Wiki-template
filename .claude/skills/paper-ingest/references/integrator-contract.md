# Integrator Agent 契约

将主提示提供的结构化提取稿和六节正文写入 LLM Wiki。所有读写在 Workflow 内完成；只在全部步骤成功后返回成功标记。

## 必须先读取

1. `{vaultRoot}/templates/论文报告模板.md`
2. `{vaultRoot}/CLAUDE.md` 中的页面规范、index 和 log 规范

将主提示中的 `vaultRoot` 替换到上述路径。不要让主会话读取这些文件。

## 写入前状态门禁

1. 从主提示的 PDF 预检清单读取 `PDF_SHA256`；缺失或格式非法时返回失败，不写入任何文件。
2. 执行：

   ```bash
   bash {vaultRoot}/.claude/skills/paper-ingest/scripts/check_ingest_state.sh "{PDF_SHA256}" "{报告目标路径}"
   ```

3. 按状态处理：
   - `NEW`：创建报告并执行全部关联写入。
   - `LEGACY`：更新旧报告，保留原 `created`，写入 `source_sha256`，再执行去重式关联更新。
   - `CHANGED`：更新报告，保留原 `created`，更新 `updated` 和 `source_sha256`，再执行去重式关联更新。
   - `UNCHANGED`：立即返回 `ACTION: SKIPPED_UNCHANGED`，不得改写报告、实体、概念、index 或 log。
   - `FAILED`：返回集成失败，不写入任何文件。

显式处理单篇论文即允许更新 `LEGACY` 或 `CHANGED` 报告；批处理是否重新处理已有报告由批处理契约控制。

## 执行顺序

1. 确保报告目标目录存在。
2. 按论文报告模板组装来源报告。
3. 创建或更新符合筛选条件的实体页面。
4. 创建或更新符合筛选条件的概念页面。
5. 更新 `wiki/index.md`。
6. 追加 `wiki/log.md`。
7. 确认以上步骤全部完成后返回短摘要。

## 来源报告

- 使用主提示提供的标题、日期、目标路径和六节正文。
- frontmatter 必须写入当前 PDF 的 `source_sha256`。
- 更新已有报告时保留原 `created`，仅把 `updated` 改为本次日期。
- 从各节“本节结论”生成顶部快速预览表，每格 1–2 句。
- 保留六节正文，不重新扩写，不恢复“核心要点”重复列表。
- 不把 `---EXISTENCE---` 及其后的 JSON 写入报告。
- 事实、作者观点和分析者推断保持原有边界。
- 成功完成全部写入后使用 `status: evergreen`；未完成时不得把失败结果标记为 evergreen。

## 实体与概念页面

- 只处理结构化提取稿清单中的实际数据行；清单为空时不创建或更新页面。
- 不为凑数量新增条目。
- `exists: false` 时按 `CLAUDE.md` 对应页面规范新建。
- `exists: true` 时先读取原页面，确认不是同名异义，再追加本文来源和关系。
- 不覆盖原有内容；以当前报告 wiki-link 为来源身份，frontmatter 和正文均不得重复添加相同来源链接。
- 仅合并原页面中尚不存在的事实或关系，不为改写措辞而重复追加同义内容。
- 新页面使用 `status: stub`，并把来源写为当前报告的 wiki-link。

## Index 与日志

- `wiki/index.md` 以页面 wiki-link 为身份，只添加尚不存在的报告、实体和概念条目。
- 来源条目包含 wiki-link、论文标题和一句话核心贡献。
- `NEW`、`LEGACY` 或 `CHANGED` 完成实际写入后，`wiki/log.md` 追加一次本次新建、更新和摘要，不修改历史日志。
- `UNCHANGED` 不追加日志；不得为同一次摄入重复写入相同条目。

## 返回契约

以下代码围栏只用于展示格式，实际返回不得包含代码围栏或任何前置说明，第一行必须是 `INTEGRATION_STATUS: OK` 或 `INTEGRATION_STATUS: FAILED`。

完成新建或更新后只返回不超过 200 个中文字符的摘要：

```text
INTEGRATION_STATUS: OK
ACTION: CREATED | UPDATED
报告: wiki/sources/... | 评分 X/10
新建: 实体 N，概念 N
更新: 实体 N，概念 N
```

状态为 `UNCHANGED` 时不得使用本轮 Writer 生成但未写入的评分，只返回：

```text
INTEGRATION_STATUS: OK
ACTION: SKIPPED_UNCHANGED
报告: wiki/sources/...
说明: PDF SHA-256 未变化，未执行写入
```

任一步骤失败时返回：

```text
INTEGRATION_STATUS: FAILED
原因: {简短原因}
```

失败时不要声称已经完成摄入。
