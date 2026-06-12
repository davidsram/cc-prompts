# Claude Code 环境搭建指南

下面是一份可直接执行的 Claude Code 环境搭建流程。每步命令可以直接粘贴到 Claude Code 对话窗口（以 `/` 开头的是交互命令），也可以用 `claude plugin ...` CLI 在终端执行。

---

## 1. 确认版本

```bash
claude --version
# 需要 ≥ 2.1.153
```

## 2. 加市场

```bash
/plugin marketplace add anthropics/skills
/plugin marketplace add obra/superpowers-marketplace
```

第二条如果已存在会提示 duplicated，不影响。

## 3. 装核心 plugin

```bash
/plugin install superpowers@superpowers-marketplace
/plugin install ralph-loop@claude-plugins-official
/plugin install skill-creator@claude-plugins-official
/plugin install frontend-design@claude-plugins-official
```

## 4. 装 Anthropic 官方 skill 集合

`anthropic-agent-skills` 市场（即上面 `anthropics/skills`）有 3 个 plugin，共含 17 个 skill：

```bash
# 文档处理：xlsx, docx, pptx, pdf
/plugin install document-skills@anthropic-agent-skills

# 示例技能：skill-creator, frontend-design, mcp-builder, algorithmic-art,
#           brand-guidelines, canvas-design, doc-coauthoring, internal-comms,
#           slack-gif-creator, theme-factory, web-artifacts-builder, webapp-testing
/plugin install example-skills@anthropic-agent-skills

# Claude API / SDK 文档
/plugin install claude-api@anthropic-agent-skills
```

## 5. 刷新生效

```bash
/reload-plugins
```

然后**重启 Claude Code**。

## 6. 验证

```bash
claude plugin list --json | jq -r '.[] | select(.enabled) | .id'
# 预期 ≥ 7 个 enabled

claude plugin marketplace list
# 预期 ≥ 4 个 market
```

---

## 关键概念：Plugin 和 Skill 的关系

最容易搞错的地方。

```
marketplace (anthropic-agent-skills)
├── plugin: document-skills          ← 用 /plugin install 装这个
│   ├── skill: xlsx                  ← 不能单独 install
│   ├── skill: docx
│   ├── skill: pptx
│   └── skill: pdf
├── plugin: example-skills           ← 用 /plugin install 装这个
│   ├── skill: skill-creator
│   ├── skill: frontend-design
│   └── ... (共 12 个)
└── plugin: claude-api               ← 用 /plugin install 装这个
    └── skill: claude-api
```

- **Plugin** = installable unit，有 `.claude-plugin/plugin.json`
- **Skill** = 寄生在 plugin 里的 `.md` 文件，装了外层 plugin 就自动可用
- **`/plugin install` 的参数必须是 plugin 名**，不能写内部的 skill 名

常见报错：
```
✘ Plugin "xlsx" not found in marketplace "anthropic-agent-skills"
```
因为 `xlsx` 是 `document-skills` plugin 的内部 skill，不是 plugin 名。

---

## 不存在的 plugin（不用浪费时间搜索）

以下名字**目前在任何已知 marketplace 都不存在**：
`data-explorer`、`data-cleaner`、`sql-analyzer`、`pandas-pro`、`visualization-expert`、`data-report`
