# 任务：实现多 provider 的 Claude Code statusline

你是一个 Claude Code 助手。用户希望给自己的 Claude Code 配置一个能显示目录、模型名、token plan 剩余量、context 使用率的 statusline。token plan 段需要按当前模型自动路由到对应 provider 的 API（5h 窗口 + weekly 窗口统一显示为 `5h N% · wk N%`）。

## 目标输出格式

statusline 渲染后类似：
```
[my-project] MiniMax M3 · 5h 74% · wk 97% · ctx:42% (58%)
```

分段规则：
- 用 ` · `（中点 + 空格）作段间分隔符，缺段时该分隔符自动消失
- model 段只显示名字，不带 `model:` 前缀
- plan 段用简洁的 `5h N%` / `wk N%` 格式，不要 `plan:5h=N%` 这种
- ctx 段用 `ctx:N% (M%)` 格式
- 任何段没数据时直接消失，不留空位

## 文件改动（3 处）

**新建** `~/.claude/statusline-plan.sh`（可执行，plan/balance 查询脚本）：
- 接受 3 个位置参数：`$1=model $2=base_url $3=api_key`
- 输出格式化的 plan/balance 字符串，或空（任何失败都静默退出 0）
- 60 秒缓存到 `/tmp/.claude_statusline_plan_${model_safe}`，key 用 model 名（lowercase + 非字母数字字符替换为 `_`）
- 2 秒 curl 超时

**新建** `~/.claude/statusline.sh`（可执行，渲染入口，见末尾"参考实现"可整段抄）：
- 从 stdin 读 Claude Code 下发的 statusline JSON
- 用 jq 抽 `.model.display_name // .model.id`、`.workspace.current_dir // .cwd`、`.transcript_path`
- ctx 段**不能**直接从 JSON 拿——Claude Code 下发的 payload 不含 `context_window` 字段，必须自己算（见下"ctx 段计算方式"）
- 调 `~/.claude/statusline-plan.sh "$model" "${ANTHROPIC_BASE_URL:-}" "${ANTHROPIC_AUTH_TOKEN:-}"` 拿 plan
- 用变量 `sep=""` 跟踪分隔符，循环给每段加 `out="${out}${sep}<段>"; sep=" · "`
- 全部包在 `\033[2m...\033[0m` 灰色 ANSI 里

**修改** `~/.claude/settings.json`，让 `statusLine` 指向 wrapper 脚本（**不要 inline 命令**）：
```json
{
  "statusLine": {
    "type": "command",
    "command": "$HOME/.claude/statusline.sh"
  }
}
```
> 教训：曾经把整条 shell 命令 inline 进 `statusLine.command` 字段——双层转义（JSON + shell）地狱、jq 的单引号要变 `'\\''`、改一次校验一次。脚本和配置解耦后，改 `statusline.sh` 不动 settings.json，调试也能直接 `bash -x ~/.claude/statusline.sh` 跑。

## ctx 段计算方式

Claude Code 真实 statusline payload 形如：
```json
{"session_id":"...","transcript_path":"/Users/.../<uuid>.jsonl","cwd":"...","workspace":{"current_dir":"...","project_dir":"..."},"model":{"id":"...","display_name":"..."},"cost":{...},"version":"...","output_style":{...},"exceeds_200k_tokens":false}
```

**没有 `context_window` 字段。** 早期文档照搬第三方示例写了这个字段，实测一律取不到，最终 statusline 只剩暗色目录名"看起来像没显示"。

正确做法：从 `transcript_path` 指向的 JSONL 里取最后一条 `usage`，加总它的 input / cache 三件套：

```bash
maxctx=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-200000}
used_tok=$(awk '/"usage"/{last=$0} END{print last}' "$tpath" 2>/dev/null \
  | jq -r '(.message.usage // .usage)
           | (.input_tokens // 0)
             + (.cache_read_input_tokens // 0)
             + (.cache_creation_input_tokens // 0)' 2>/dev/null || echo 0)
pct=$(awk -v u="$used_tok" -v m="$maxctx" 'BEGIN{if(m>0)printf "%.0f", u*100/m; else print 0}')
rem=$((100 - pct))
```

要点：
- `awk` 找最后一条含 `"usage"` 的 JSONL 行（macOS 默认无 `tac`，且 statusline 子 shell 不一定带 brew PATH）
- `usage` 可能在 `.message.usage`（assistant turn）或顶层 `.usage`（compaction 摘要），都兼容
- 加总 `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`，否则跟 Claude Code 内部账本对不上（cache hit 占了大头）
- 分母走 `CLAUDE_CODE_MAX_CONTEXT_TOKENS` 环境变量，没设就用 200000 兜底（1M 上下文用户应该已经在 settings.json 的 env 里设过这个值，statusline 子进程会继承）
- `used_tok=0` 时不输出 ctx 段（新会话还没有 assistant turn，避免显示 `ctx:0% (100%)` 噪音）

## Provider 路由矩阵

按 `model` 小写匹配（ZenMux 是 base URL 匹配例外）：

| 触发 model 关键字 | provider | endpoint | 鉴权 | 关键字段 | 重要陷阱 |
|---|---|---|---|---|---|
| `minimax` / `abab` | MiniMax | `{host}/v1/api/openplatform/coding_plan/remains` | `Authorization: Bearer $key` | `model_remains[model_name=general].current_interval_remaining_percent`、`current_weekly_remaining_percent` | host 默认 `https://api.minimaxi.com`（gateway 也直连，不被 base_url 绑架）；**只显示 status==1 的窗口** |
| `kimi` / `moonshot` | Kimi | `https://api.kimi.com/coding/v1/usages` | `Authorization: Bearer $key` | `limits[0].detail.{limit,remaining}`（5h）、`usage.{limit,remaining}`（wk） | 给的是 utilization（已用%），要 `100 - (1-remaining/limit)*100` 反转 |
| `glm` | 智谱 GLM | `{host}/api/monitor/usage/quota/limit` | **`Authorization: $key` 无 Bearer 前缀** | `data.limits[].{unit,percentage,type}` | unit 3=5h、6=wk；filter `type=="TOKENS_LIMIT"`；utilization 反转；`success==false` 视为空 |
| base URL 含 `zenmux` | ZenMux | `{base_url}` | `Authorization: Bearer $key` | `data.quota_5_hour.usage_percentage`、`data.quota_7_day.usage_percentage` | **唯一按 base URL 路由**（ZenMux 是代理，model 任意）；`usage_percentage` 是 0-1 分数不是 0-100；反转公式 `(1-frac)*100`；`success!=true` 视为空 |
| `deepseek` | DeepSeek | `https://api.deepseek.com/user/balance` | `Authorization: Bearer $key` | `balance_infos[].{currency,total_balance}` | 输出金额格式 `¥ 12.34` / `$ 5.67`（多个币种用 ` / ` 分隔）；`total_balance==0` 的不进位；默认币种 CNY |

**重要：3 家（Kimi/Zhipu/ZenMux）的 API 返回 utilization（已用%），statusline 要的是 remaining%（未用%），必须反转。** 唯独 MiniMax 直接给 remaining%。

## 字段路径权威来源

不要靠猜——加新 provider 时去 `https://github.com/farion1231/cc-switch` 的 `src-tauri/src/services/coding_plan.rs` 和 `balance.rs` 看 `query_xxx` 函数的 Rust 实现，逐字抄 endpoint、headers、JSON 字段路径。cc-switch 已支持 9+ 家。

## 测试

写两个测试脚本：

**1. 合成 JSON 单测**——对每个 provider 准备 2-3 个合成响应，跑 jq 解析逻辑，断言输出字符串：
- 正常（两窗口都有）
- 部分缺失（只 5h、只 wk）
- 错误场景（auth fail、success=false、no general model、balance=0）

**2. 端到端 statusline 测**——用 `env -i PATH=... ANTHROPIC_BASE_URL=... ANTHROPIC_AUTH_TOKEN=... bash -c "$statusline_cmd" <<< "$sample_json"` 跑 8 个场景：
- minimax 模型 + minimax base + 真 key → plan 显示
- minimax 模型 + zenmux base + 真 key → plan 仍显示（验证兜底）
- deepseek/kimi/glm 模型 + 真 key → 静默（因为 key 不是对应 provider 的，会 auth fail）
- zenmux base + 任意 model → 走 ZenMux 分支
- 未知 model + 未知 base → plan 隐藏，model/ctx 还在
- 缺 key → plan 隐藏

`sample_json` 模板（贴近真实 Claude Code statusline payload）：
```json
{"session_id":"abc","transcript_path":"/tmp/fake-transcript.jsonl","cwd":"/Users/me/proj","workspace":{"current_dir":"/Users/me/proj","project_dir":"/Users/me/proj"},"model":{"id":"MiniMax-M3","display_name":"MiniMax M3"},"version":"2.x","cost":{"total_cost_usd":0}}
```

为了让 ctx 段有值，端到端测试前先写一份假 transcript：
```bash
printf '%s\n' '{"message":{"usage":{"input_tokens":100,"cache_read_input_tokens":419000,"cache_creation_input_tokens":1500}}}' > /tmp/fake-transcript.jsonl
```
（这条对应 1M context 下 ~42% 用量）

## 行为约定

- **静默失败**：任何错误（curl 失败、JSON 解析失败、jq 报错、auth 失败、响应里没数据）→ 脚本 exit 0 不输出。不允许把错误消息透到 statusline（终端一闪一闪很丑）。
- **缓存粒度按 model**：用户切换 model 时不同 provider 的缓存互不污染。`safe_model` 用 `printf '%s' "$model" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_'` 生成。
- **不在 60s TTL 内反复打 API**：用 `[ -f "$CACHE" ]` + `stat -f %m`（macOS）/ `stat -c %Y`（Linux）检查 mtime。
- **不要在脚本里写 set -e**：静默失败需要 set -u 即可，加 -e 会让所有 error 暴露。
- **jq 调用统一加 `-rc`**：compact + raw output，避免 head -n1 截断多行 JSON。
- **percent 值验证**：用 `case "$x" in ''|*[!0-9.]*) ...` 检查数字，避免脏数据时 jq 出 NaN/garbage。

## 不要做的事

- 不要加 `model:` `plan:` `ctx:` 这种 label 前缀（用户明确拒绝过）
- 不要在 statusline 里加 emoji 或彩条
- 不要为单 provider 写死字段，通用化以支持以后扩展
- 不要在 plan 脚本里 echo 任何错误到 stdout/stderr

## 实施步骤

1. 写 `~/.claude/statusline-plan.sh`，先只支持 minimax，`chmod +x`，命令行验证：
   `~/.claude/statusline-plan.sh "MiniMax M3" "$ANTHROPIC_BASE_URL" "$ANTHROPIC_AUTH_TOKEN"` 应输出 `5h N% · wk N%`
2. 写 `~/.claude/statusline.sh`（可整段抄"参考实现"节），`chmod +x`
3. 端到端验 `statusline.sh`：写假 transcript + 喂假 payload（见"测试"节第 2 部分）
4. 修改 `~/.claude/settings.json` 的 `statusLine.command` 指向 `$HOME/.claude/statusline.sh`，`jq -e` 校验 JSON 合法
5. Claude Code 重渲染 statusline（任意输入或工具调用会触发）—— 看到 `[dir] · model · 5h N% · wk N% · ctx:N% (M%)` 即成功
6. 再加 kimi/zhipu/zenmux/deepseek 到 plan 脚本，每加一家跑一次合成 JSON 单测

## 参考实现：`~/.claude/statusline.sh`

整段可直接抄。已实战验证过 macOS（zsh 默认 shell、无 `tac`、statusline 子 shell 无 brew PATH 也能跑）：

```bash
#!/bin/bash
# statusline.sh — renders the Claude Code statusline
# Reads statusline JSON from stdin, outputs formatted statusline to stdout.
#
# Format: [dir] · model · plan/balance · ctx:used% (remaining%)
# Segments auto-hide when data is missing. Separator " · " tracks via $sep.

set -u

input=$(cat)
model=$(echo "$input" | jq -r '(.model.display_name // .model.id // empty)' 2>/dev/null)
tpath=$(echo "$input" | jq -r '(.transcript_path // empty)' 2>/dev/null)
cwd=$(echo "$input" | jq -r '(.workspace.current_dir // .cwd // empty)' 2>/dev/null)
if [ -n "$cwd" ]; then
  dir=$(basename "$cwd")
else
  dir=$(basename "$(pwd)")
fi

plan=$($HOME/.claude/statusline-plan.sh "$model" "${ANTHROPIC_BASE_URL:-}" "${ANTHROPIC_AUTH_TOKEN:-}" 2>/dev/null)

# ctx: compute from transcript_path — Claude Code's statusline JSON does NOT
# carry context_window fields, so we read the last "usage" line from the
# transcript JSONL and sum input + cache_read + cache_creation tokens.
maxctx=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-200000}
used_tok=0
if [ -n "$tpath" ] && [ -f "$tpath" ]; then
  used_tok=$(awk '/"usage"/{last=$0} END{print last}' "$tpath" 2>/dev/null \
    | jq -r '(.message.usage // .usage)
             | (.input_tokens // 0)
               + (.cache_read_input_tokens // 0)
               + (.cache_creation_input_tokens // 0)' 2>/dev/null)
  case "$used_tok" in ''|*[!0-9]*) used_tok=0 ;; esac
fi

sep=""
out=""

# [dir]
out="${out}${sep}[${dir}]"
sep=" · "

# model
case "$model" in ""|null) ;; *)
  out="${out}${sep}${model}"
  ;;
esac

# plan/balance (from statusline-plan.sh)
if [ -n "$plan" ]; then
  out="${out}${sep}${plan}"
fi

# ctx:used% (remaining%)
if [ "$used_tok" -gt 0 ] && [ "$maxctx" -gt 0 ]; then
  pct=$(awk -v u="$used_tok" -v m="$maxctx" 'BEGIN{printf "%.0f", u*100/m}')
  rem=$((100 - pct))
  out="${out}${sep}ctx:${pct}% (${rem}%)"
fi

printf "\033[2m%s\033[0m" "$out"
```

## 完成后检查

- 真实 minimax key → 应该看到 `5h N% · wk N%`
- 切到 deepseek 模型 → plan 段消失，余额格式正确（需要 deepseek 真 key）
- 切到 claude-sonnet → plan 段消失
- 长时间不动 statusline（>60s）→ API 调用频率不超过 1 次/60s/model

## 排错

| 症状 | 根因 | 修法 |
|---|---|---|
| 整条 statusline 完全看不到 / 只剩暗色 `[dir]` | 读了不存在的字段（如 `.context_window.used_percentage`），所有段都是空字符串 | 重读"ctx 段计算方式"——Claude Code 真实 payload 形状以验证字段路径存在 |
| `ctx:0% (100%)` 一直显示 | 新会话还没有 assistant turn，transcript 里没 `"usage"` 行；或 transcript 路径错 | 加 `[ "$used_tok" -gt 0 ]` 守卫；`ls -la "$tpath"` 验证路径 |
| ctx% 比 Claude Code 内部账本小很多 | 只加了 `input_tokens`，漏了 `cache_read_input_tokens` 和 `cache_creation_input_tokens`（cache hit 占大头） | 三件套必须全加 |
| plan 段不显示但 `~/.claude/statusline-plan.sh ...` 命令行能跑 | statusline 子 shell 没继承 `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL` | 验证 `~/.claude/settings.json` 的 `env` 块里有这俩值 |
| 改 `statusLine.command` 后没生效 | settings 监视器只盯会话启动时已存在的 settings 文件目录 | `/hooks` 菜单走一遍触发重载，或重启 Claude Code |
| `tac: command not found` | macOS 默认无 `tac`，statusline 子 shell 也不一定带 brew PATH | 用 `awk '/"usage"/{last=$0} END{print last}'` 替代 |
| 切 model 后 plan 段瞎报数 | 缓存 key 没按 model 分粒度，A model 的缓存被 B model 用 | `safe_model=$(printf '%s' "$model" \| tr '[:upper:]' '[:lower:]' \| tr -c 'a-z0-9' '_')` 进 cache 文件名 |
