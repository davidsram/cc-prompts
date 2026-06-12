# 任务：批量安装 Claude Code 插件

你是一个 Claude Code 助手。用户希望批量安装一批 Claude Code 插件（plugin）以便开启新机器 / 新账号时一键复现工作环境。

## 目标

完成下面 4 段命令后，用户在 Claude Code 里有：

- 两个额外 marketplace 来源（`anthropics/skills` 和 `obra/superpowers-marketplace`）
- 3 个核心插件：`superpowers` / `ralph-loop` / `skill-creator`
- 6 个数据分析插件：`data-explorer` / `data-cleaner` / `sql-analyzer` / `pandas-pro` / `visualization-expert` / `data-report`
- 已通过 `/reload-plugins` 生效

## 命令序列

按顺序执行，每段单独跑（前面的报错不会影响后面）：

```bash
# 1. 加市场
/plugin marketplace add anthropics/skills
/plugin marketplace add obra/superpowers-marketplace

# 2. 核心 3 个
/plugin install superpowers@superpowers-marketplace
/plugin install ralph-loop@openclaw
/plugin install skill-creator@anthropic-agent-skills

# 3. 数据分析常用
/plugin install data-explorer@anthropic-agent-skills
/plugin install data-cleaner@anthropic-agent-skills
/plugin install sql-analyzer@anthropic-agent-skills
/plugin install pandas-pro@anthropic-agent-skills
/plugin install visualization-expert@anthropic-agent-skills
/plugin install data-report@anthropic-agent-skills

# 4. 刷新生效
/reload-plugins
```

## 验证

```bash
# 看已启用的 plugins（应包含 9 个）
cat ~/.claude/settings.json | jq '.enabledPlugins'

# 看已知的 marketplaces
cat ~/.claude/settings.json | jq '.extraKnownMarketplaces'
```

期望 `enabledPlugins` 含：
- `superpowers@<market>`、`ralph-loop@<market>`、`skill-creator@<market>`
- 6 个 data-* 插件

期望 `extraKnownMarketplaces` 含：
- `anthropics/skills` 来源
- `obra/superpowers-marketplace` 来源

## 已知问题（执行前先核 marketplace alias）

- `anthropics/skills` 在 Anthropic 官方仓库名是 `anthropics/claude-plugins-community`，请先在 Anthropic 官方文档 / GitHub 确认这个名字是否正确。
- `openclaw`、`anthropic-agent-skills` 这两个 marketplace alias 看起来是别名而非 GitHub 仓库。常见真实 alias 是 `claude-plugins-official` / `claude-community` 之类。执行前用 `/plugin marketplace list` 看一下当前已注册的市场，**用真实的 alias 替换命令中的 `@xxx` 后缀**。
- `data-explorer` / `data-cleaner` / `sql-analyzer` / `pandas-pro` / `visualization-expert` / `data-report` 这 6 个插件在 Anthropic 官方 `claude-plugins-community` 中**不一定存在**。如果 `/plugin install` 报 "not found"，说明那个 marketplace 并没有这个插件——需要换一个能提供数据分析能力的 marketplace，或找等价插件。
- 命令里很多 `<plugin>@<market>` 的 `<market>` 部分如果写错，命令会静默失败或报 unknown marketplace。装完一定要跑上面 `jq` 验证命令确认 enabledPlugins 真的增加了。

## 不要做的事

- 不要把所有 plugin 一次性 install，不分核心和数据分析两个 group 一起跑
- 不要用 force / --no-verify 之类绕过 marketplace 校验
- 不要在命令里加 `--global` 之类未在文档出现的 flag（Claude Code 的 `/plugin` 子命令 flag 集合随时在变）

## 实施步骤

1. 跑 `/plugin marketplace list` 确认当前已有的市场 alias
2. 把本 prompt 命令序列里的 `<market>` 后缀按实际 alias 替换
3. 按 1 → 2 → 3 → 4 顺序执行（用 `/plugin` 交互命令，不是 shell 命令）
4. 跑验证段 `jq` 命令
5. 重启 Claude Code 看新插件是否在 `/` 命令面板里出现

## 完成后检查

- `/` 面板里能看到 9 个新插件的命令
- 当前会话里 `/help` 输出里多了这些 skill 名字
- 删除 1-2 个插件测试能否干净卸载（`/plugin uninstall xxx@xxx`），确认 rollback 路径可用
