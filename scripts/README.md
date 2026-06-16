# statusline scripts

可安装的 Claude Code statusline 实现，对应 `prompts/claude-code-statusline.md` 的设计文档。

## 文件清单

| 脚本 | 安装位置 | 作用 |
|------|----------|------|
| `statusline.sh` | `~/.claude/statusline.sh` | 渲染入口。从 stdin 读 Claude Code 下发的 statusline JSON，输出 `[dir] · model · plan · ctx` 格式 |
| `statusline-plan.sh` | `~/.claude/statusline-plan.sh` | 查询 provider 的 plan/balance，5 家 provider 自动路由（MiniMax/Kimi/Zhipu/ZenMux/DeepSeek） |
| `fix-statusline.sh` | `~/.claude/fix-statusline.sh` | 防 `cc switch` 覆写 `~/.claude/settings.json` 时把 `statusLine.command` 回退 |

## 安装

```bash
# 拷贝脚本
cp scripts/statusline.sh scripts/statusline-plan.sh scripts/fix-statusline.sh ~/.claude/
chmod +x ~/.claude/statusline.sh ~/.claude/statusline-plan.sh ~/.claude/fix-statusline.sh

# 修改 ~/.claude/settings.json 的 statusLine.command 指向 wrapper
# （直接编辑或运行 fix-statusline.sh 自动修复）
jq --arg cmd "$HOME/.claude/statusline.sh" \
   '.statusLine = {"type":"command","command":$cmd}' \
   ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

## 防覆写配置（项目级）

把下面的 hook 加到**当前项目**的 `.claude/settings.local.json`（已被 `.gitignore` 忽略，不提交）：

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/fix-statusline.sh",
            "timeout": 5,
            "statusMessage": "Verifying statusline config..."
          }
        ]
      }
    ]
  }
}
```

每次 Bash 命令执行后自动校验 `statusLine.command` 是否正确，不对就修回去。

## 验证

```bash
# 假 transcript（含 cache tokens，模拟 ~42% context）
printf '%s\n' \
  '{"message":{"usage":{"input_tokens":100,"cache_read_input_tokens":419000,"cache_creation_input_tokens":1500}}}' \
  > /tmp/fake-transcript.jsonl

# 假 payload
echo '{"session_id":"abc","transcript_path":"/tmp/fake-transcript.jsonl","cwd":"/tmp","workspace":{"current_dir":"/tmp","project_dir":"/tmp"},"model":{"id":"MiniMax-M3","display_name":"MiniMax M3"},"version":"2.x","cost":{"total_cost_usd":0}}' \
  | bash ~/.claude/statusline.sh
# 期望输出（灰色）：[tmp] · MiniMax M3 · 5h N% · wk N% · ctx:40% (60%)
```

## 设计参考

完整的设计文档、字段路径、provider 路由矩阵、ctx 段计算方式见 [`prompts/claude-code-statusline.md`](../prompts/claude-code-statusline.md)。