# cc-prompts

Claude Code 相关的配置 prompt 集合。每一个 prompt 是可直接贴给另一个 Claude Code 实例的自包含任务说明，能让对方快速复现某项配置。

## 目录

- `prompts/claude-code-setup-guide.md` — **新机上手第一条**：一键搭建环境（装 market + plugin + skill）
- `prompts/claude-code-statusline.md` — 多 provider statusline（dir + model + token plan + ctx）

## 命名约定

`prompts/<claude-code-子领域>.md` —— 文件名描述 prompt 解决的具体配置问题，不带日期/版本号，方便后续合并同类。

## 使用方式

在 Claude Code 中打开本项目目录，然后说：

> 依次读取 `prompts/` 下的每个文件，按顺序执行其中的配置步骤
