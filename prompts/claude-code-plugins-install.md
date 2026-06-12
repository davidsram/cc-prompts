# 任务：批量安装 Claude Code 插件与技能

你是一个 Claude Code 助手。用户希望在新机器上复现工作环境：加 marketplace、装核心 plugin（含 skill）。

**交互方式**：本 prompt 的命令是 Claude Code 的 `/plugin` 交互命令，直接在对话窗口粘贴执行。也可用等效的 `claude plugin` CLI 命令（在终端里跑）。

## 前提条件

```bash
claude --version
# 确保 ≥ 2.1.153
```

## 第一步：确认当前状态

```bash
claude plugin list --json | jq -r '.[] | "\(.id)  enabled=\(.enabled)"'
claude plugin marketplace list
```

## 第二步：加市场

```bash
/plugin marketplace add anthropics/skills
/plugin marketplace add obra/superpowers-marketplace
```

`anthropics/skills` → alias 自动变成 `anthropic-agent-skills`。
`superpowers-marketplace` 如果已存在会提示 duplicated，不影响。

## 第三步：装核心 plugin

```bash
# superpowers — plan / code review / debug / TDD 等
/plugin install superpowers@superpowers-marketplace

# ralph-loop — 自动化 loop
/plugin install ralph-loop@claude-plugins-official

# skill-creator — 创建自定义 skill（claude-plugins-official 里的独立 plugin 版本）
/plugin install skill-creator@claude-plugins-official
```

每个装完用 `claude plugin list --json | jq` 确认 enabled=true。

## 第四步：装 Anthropic 官方 skill 集合

`anthropic-agent-skills` 市场有 3 个 plugin，共含 17 个 skill：

| Plugin 名 | 含的 skill | 安装命令 |
|---|---|---|
| `document-skills` | xlsx, docx, pptx, pdf | `/plugin install document-skills@anthropic-agent-skills` |
| `example-skills` | skill-creator, frontend-design, mcp-builder, algorithmic-art, brand-guidelines, canvas-design, doc-coauthoring, internal-comms, slack-gif-creator, theme-factory, web-artifacts-builder, webapp-testing | `/plugin install example-skills@anthropic-agent-skills` |
| `claude-api` | claude-api 文档 | `/plugin install claude-api@anthropic-agent-skills` |

```bash
/plugin install document-skills@anthropic-agent-skills
/plugin install example-skills@anthropic-agent-skills
/plugin install claude-api@anthropic-agent-skills
```

## 关键概念：Plugin 和 Skill 的关系

这是最容易踩的坑。

- **Plugin** = installable unit，有 `.claude-plugin/plugin.json` 清单。用 `/plugin install` 安装。
- **Skill** = 寄生在 plugin 里的单个功能模块，用 `SKILL.md` 定义。**不能单独 install**，装了外层 plugin 自动获得。

```
marketplace (anthropic-agent-skills)
├── plugin: document-skills          ← 这个能 install
│   ├── skill: xlsx                  ← 这个不能单独 install
│   ├── skill: docx
│   ├── skill: pptx
│   └── skill: pdf
├── plugin: example-skills           ← 这个能 install
│   ├── skill: skill-creator
│   ├── skill: frontend-design
│   ├── skill: mcp-builder
│   └── ... (共 12 个 skill)
└── plugin: claude-api               ← 这个能 install
    └── skill: claude-api
```

**常见报错**：

```
✘ Plugin "skill-creator" not found in marketplace "anthropic-agent-skills"
```

因为 `skill-creator` 是这个 market 里**某个 plugin 的内部 skill 名**，不是 plugin 名。正确做法是装 `example-skills@anthropic-agent-skills`（或装独立的 `skill-creator@claude-plugins-official`）。

## 第五步：刷新生效

```bash
/reload-plugins
```

然后**重启 Claude Code**，skill 才会出现在 `/` 命令面板。

## 验证

```bash
# enabled plugin 列表（预期 ≥ 7 个）
claude plugin list --json | jq -r '.[] | select(.enabled) | .id'

# market 列表（≥ 4 个）
claude plugin marketplace list
```

## 不存在的东西（不用浪费时间找）

以下 plugin / skill 名**目前在已知 marketplace 都不存在**：
- `data-explorer` / `data-cleaner` / `sql-analyzer`
- `pandas-pro` / `visualization-expert` / `data-report`
- `ralph-loop@openclaw`（`openclaw` 市场不存在）

## 不要做的事

- 不要在 `@anthropic-agent-skills` 后面写 skill 名（`xlsx`、`skill-creator`）—— 要写 plugin 名（`document-skills`、`example-skills`）
- 不要把所有 plugin 一次性全装不验证——装一个、查一个
- 不要硬找不存在的 plugin，浪费时间

## 实施步骤

1. 第一步确认初始状态
2. 第二步加两个 market
3. 第三步装了 3 个核心 plugin
4. 第四步装 3 个 skill plugin
5. `/reload-plugins` + 重启 CC
6. 验证段确认 ≥ 7 个 enabled
