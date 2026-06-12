# 任务：批量安装 Claude Code 插件

你是一个 Claude Code 助手。用户希望在一台新机器 / 新账号上快速复现 Claude Code 的工作环境：装 marketplace、装核心 plugin、装数据分析类 plugin。

**重要**：本 prompt 里的命令是交互式 `/plugin` 命令，不是 shell 命令。直接在 Claude Code 对话窗口里粘贴执行即可。

## 前提条件

```bash
claude --version
# 确保 ≥ 2.1.153（插件市场支持完整）
```

## 第一步：确认当前状态

先跑一遍查询，看看现在有多少 plugin 和 market，后面好对比：

```bash
claude plugin list --json | jq -r '.[] | "\(.id)  enabled=\(.enabled)"'
claude plugin marketplace list
```

## 第二步：加市场

```bash
# 官方 plugin 市场（通常预装，不用加）
# 社区市场 — Anthropic 官方的 skill 集合（注意：这个是 skill 市场，不是 plugin 市场）
/plugin marketplace add anthropics/skills

# Superpowers 市场
/plugin marketplace add obra/superpowers-marketplace
```

**知识**：`marketplace add` 接受 GitHub 仓库名 `org/repo`，自动转换成内部 alias。`anthropics/skills` 转换后 alias = `anthropic-agent-skills`（里面全是 SKILL.md，没有 plugin.json，所以 `/plugin install xxx@anthropic-agent-skills` 会报 not found —— 这是正常的，skill 另外加载不经过 install）。

## 第三步：装核心 plugin

```bash
# superpowers — 写 plan / code review / debug / TDD 等 18 个流程 skill
# 两个市场都有，选一个即可
/plugin install superpowers@superpowers-marketplace

# ralph-loop — 自动化 loop 控制
/plugin install ralph-loop@claude-plugins-official

# frontend-design — 前端设计生成
/plugin install frontend-design@claude-plugins-official

# skill-creator — 创建自定义 skill（从 claude-plugins-official 装 plugin 版）
/plugin install skill-creator@claude-plugins-official
```

**如果不知道 plugin 在哪个市场**，可以先不写 `@xxx` 后缀，Claude Code 会自动搜：

```bash
/plugin install ralph-loop
/plugin install skill-creator
/plugin install frontend-design
```

## 第四步：装第三方 plugin（按需）

其它社区好用的 plugin，确认存在的：

```bash
# everything-claude-code — meta 集合
/plugin install everything-claude-code@everything-claude-code
```

数据分析类 plugin（`data-explorer`、`pandas-pro`、`sql-analyzer` 等）**目前在任何已知 marketplace 都不存在**。如果以后出现了，也可以 `/plugin install xxx@marketplace`。

## 第五步：刷新生效

```bash
/reload-plugins
```

重启 Claude Code，确保新 plugin 的命令出现在 `/` 面板里。

## 验证

```bash
# 看已启用的 plugin（≥ 5 个 enabled）
claude plugin list --json | jq -r '.[] | select(.enabled) | .id'

# 看已知 markets（≥ 4 个）
claude plugin marketplace list
```

## 概念区分：Skill vs Plugin

Claude Code 有两种扩展方式，容易混：

| | Plugin | Skill |
|---|---|---|
| 清单文件 | `.claude-plugin/plugin.json` | `SKILL.md` |
| 安装方式 | `/plugin install xxx@market` | 不能 install，靠 `--plugin-dir` 或 marketplace auto-load |
| 内容 | commands、hooks、MCP、agents | 一个 skill 说明文档 |
| 例子 | `superpowers`、`ralph-loop`、`skill-creator` | `anthropic-agent-skills` 里的 18 个 skill |

`anthropic-agent-skills` 是一个 **skill 市场**，0 个 plugin。你 `marketplace add` 它之后，里面的 skill（`xlsx`、`pdf`、`pptx`、`docx`、`claude-api`、`mcp-builder` 等 17 个）会被 Claude Code 自动识别，不需要 `/plugin install`。删了 marketplace 就看不到了。

## 不要做的事

- 不要所有 plugin 一次装完不验证——装一个、查一下 `claude plugin list`、再装下一个
- 不要用 `claude plugin install` 装 `@anthropic-agent-skills` 下的东西（它是 skill 市场，install 会报 not found）
- 不要硬找 `data-explorer` / `pandas-pro` / `sql-analyzer` 等不存在的数据分析 plugin——等它们日后出现再装
- 不要在 `@openclaw`、`@anthropic-agent-skills` 这种不存在的 alias 下找 plugin

## 实施步骤

1. 跑第一步确认当前状态
2. 跑第二步加市场（第二条 `superpowers-marketplace` 可能已存在，报 duplicated 也不影响）
3. 跑第三步装 `superpowers` / `ralph-loop` / `skill-creator`（不加 `@xxx` 后缀，让 CC 自动搜）
4. 跑第四步按需装其它
5. 跑 `/reload-plugins` 刷新
6. 跑验证段
7. 重启 CC，用 `/` 看新命令面板是否更新

## 完成后检查

- `/` 命令面板能看到 `superpowers:xxx` / `ralph-loop:xxx` 等新命令
- `claude plugin list --json | jq -r '.[].enabled'` 至少有 5 个 true
- 删掉一个不需要的 plugin 确认 rollback 路径可用
