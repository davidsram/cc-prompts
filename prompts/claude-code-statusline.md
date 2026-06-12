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

## 文件改动

**新建** `~/.claude/statusline-plan.sh`（可执行）：
- 接受 3 个位置参数：`$1=model $2=base_url $3=api_key`
- 输出格式化的 plan/balance 字符串，或空（任何失败都静默退出 0）
- 60 秒缓存到 `/tmp/.claude_statusline_plan_${model_safe}`，key 用 model 名（lowercase + 非字母数字字符替换为 `_`）
- 2 秒 curl 超时

**修改** `~/.claude/settings.json` 的 `statusLine.command` 字段：
- 从 stdin 读 statusline JSON（`cat`），用 jq 提取 `.model.display_name // .model.id // empty`、`.context_window.used_percentage // empty`、`.context_window.remaining_percentage // empty`
- 调 `~/.claude/statusline-plan.sh "$model" "${ANTHROPIC_BASE_URL:-}" "${ANTHROPIC_AUTH_TOKEN:-}"` 拿 plan
- 用变量 `sep=""` 跟踪分隔符，循环给每段加 `printf "%s%s" "$sep" "段内容"; sep=" · "`
- 全部包在 `\033[2m...\033[0m` 灰色 ANSI 里

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

`sample_json` 模板：`{"model":{"id":"MiniMax-M3","display_name":"MiniMax M3"},"context_window":{"used_percentage":42,"remaining_percentage":58}}`

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

1. 写 `~/.claude/statusline-plan.sh`，先只支持 minimax，验证能用真 key 跑通
2. 跑 8 个端到端场景，全过再继续
3. 加 kimi/zhipu/zenmux/deepseek 4 家，每加一家跑一次合成 JSON 单测
4. 修改 `~/.claude/settings.json` 的 `statusLine.command`
5. 重启 Claude Code 看实际渲染效果

## 完成后检查

- 真实 minimax key → 应该看到 `5h N% · wk N%`
- 切到 deepseek 模型 → plan 段消失，余额格式正确（需要 deepseek 真 key）
- 切到 claude-sonnet → plan 段消失
- 长时间不动 statusline（>60s）→ API 调用频率不超过 1 次/60s/model
