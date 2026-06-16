#!/bin/bash
# statusline-plan.sh MODEL BASE_URL API_KEY
# Outputs a formatted plan/balance string for the statusline, or empty on any failure.
# Caches 60s per (provider, model). Always exits 0 silently.
#
# Providers (dispatched by model, with ZenMux as a base-URL exception):
#
#   minimax | abab   → coding_plan/remains        remaining% per window (status==1)
#   kimi | moonshot  → coding/v1/usages           utilization% per window, INVERT to remaining
#   glm              → quota/limit                 utilization% by unit 3/6, INVERT, NO Bearer
#   deepseek         → user/balance                ¥/$ amount per currency
#   *zenmux* base    → {base_url}                  quota_5_hour/quota_7_day, INVERT fraction*100
#
# "INVERT" means the API returns % used (utilization) or fraction used; we want % remaining.

set -u

MODEL=${1:-}
BASE_URL=${2:-}
API_KEY=${3:-}

[ -z "$API_KEY" ] && exit 0
[ -z "$MODEL" ] && exit 0

mlc=$(printf '%s' "$MODEL" | tr '[:upper:]' '[:lower:]')

TIMEOUT=2
safe_model=$(printf '%s' "$mlc" | tr -c 'a-z0-9' '_')
CACHE="/tmp/.claude_statusline_plan_${safe_model}"
TTL=60

# Cache check
now=$(date +%s)
if [ -f "$CACHE" ]; then
  mtime=$(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null || echo 0)
  if [ -n "$mtime" ] && [ $((now - mtime)) -lt $TTL ]; then
    cat "$CACHE"
    exit 0
  fi
fi

curl_json() {
  curl -s -m "$TIMEOUT" "$1" -H "Accept: application/json" "${@:2}" 2>/dev/null
}

# ---- MiniMax ----
# endpoint: {host}/v1/api/openplatform/coding_plan/remains, Bearer
# response: model_remains[model_name=general].{current_interval_remaining_percent, current_weekly_remaining_percent}
# already in remaining% — no inversion
# Host detection: prefer the user's actual base URL, but fall back to api.minimaxi.com
# so that gateways (e.g. ZenMux proxying MiniMax) still work — the plan query
# always hits MiniMax's API directly, not the gateway.
fetch_minimax() {
  local host
  case "$BASE_URL" in
    *minimax.io*)   host="https://api.minimax.io" ;;
    *minimaxi.com*) host="https://api.minimaxi.com" ;;
    *)              host="https://api.minimaxi.com" ;;
  esac
  local resp
  resp=$(curl_json "${host}/v1/api/openplatform/coding_plan/remains" \
    -H "Authorization: Bearer ${API_KEY}") || return 1
  printf '%s' "$resp" | jq -rc '
    (.model_remains[]? | select(.model_name=="general")) as $g
    | [
        (if $g.current_interval_status==1 then "5h \($g.current_interval_remaining_percent)%" else empty end),
        (if $g.current_weekly_status==1 then "wk \($g.current_weekly_remaining_percent)%" else empty end)
      ] | map(select(. != "")) | join(" · ")
  ' 2>/dev/null
}

# ---- Kimi ----
# endpoint: https://api.kimi.com/coding/v1/usages, Bearer
# response: limits[].detail.{limit, remaining, resetTime}, usage.{limit, remaining, resetTime}
# utilization = (limit-remaining)/limit*100  →  remaining = 100 - utilization
# Use first limit for 5h; usage is weekly
fetch_kimi() {
  local resp
  resp=$(curl_json "https://api.kimi.com/coding/v1/usages" \
    -H "Authorization: Bearer ${API_KEY}") || return 1
  printf '%s' "$resp" | jq -rc '
    def remaining_pct(used_pct): if used_pct == null then empty else (100 - used_pct) end;
    (([.limits[]?.detail] | .[0]) // null) as $first_limit
    | (if $first_limit and $first_limit.limit > 0
       then ((1 - ($first_limit.remaining / $first_limit.limit)) * 100)
       else null end) as $five_used
    | (if .usage and .usage.limit > 0
       then ((1 - (.usage.remaining / .usage.limit)) * 100)
       else null end) as $wk_used
    | [
        (if $five_used != null then "5h " + (100 - $five_used | floor | tostring) + "%" else empty end),
        (if $wk_used != null then "wk " + (100 - $wk_used | floor | tostring) + "%" else empty end)
      ] | map(select(. != "")) | join(" · ")
  ' 2>/dev/null
}

# ---- Zhipu GLM ----
# endpoint: {host}/api/monitor/usage/quota/limit, NO Bearer prefix, just the key
# response: {success, data: {limits: [{unit, percentage, type, nextResetTime}], level}}
# unit: 3 = 5h, 6 = weekly.  percentage = utilization (used%); invert.
# Filter by type == "TOKENS_LIMIT" (case-insensitive)
fetch_zhipu() {
  local host
  case "$BASE_URL" in
    *z.ai*)         host="https://api.z.ai" ;;
    *bigmodel.cn*)  host="https://open.bigmodel.cn" ;;
    *)              return 1 ;;
  esac
  local resp
  resp=$(curl_json "${host}/api/monitor/usage/quota/limit" \
    -H "Authorization: ${API_KEY}") || return 1
  printf '%s' "$resp" | jq -rc '
    if .success == false then empty
    else
      ([.data.limits[]? | select((.type // "" | ascii_upcase) == "TOKENS_LIMIT")]
       | map(select(.unit == 3)) | .[0].percentage // null) as $five_used
      | ([.data.limits[]? | select((.type // "" | ascii_upcase) == "TOKENS_LIMIT")]
         | map(select(.unit == 6)) | .[0].percentage // null) as $wk_used
      | [
          (if $five_used != null then "5h " + (100 - $five_used | floor | tostring) + "%" else empty end),
          (if $wk_used   != null then "wk " + (100 - $wk_used   | floor | tostring) + "%" else empty end)
        ] | map(select(. != "")) | join(" · ")
    end
  ' 2>/dev/null
}

# ---- ZenMux (base-URL exception) ----
# endpoint: {base_url} directly, Bearer
# response: {success, data: {quota_5_hour: {usage_percentage}, quota_7_day: {usage_percentage}, plan, account_status}}
# usage_percentage is a FRACTION (0-1); remaining% = (1 - frac) * 100
# Only dispatch if base URL contains "zenmux" — not model-based.
fetch_zenmux() {
  local resp
  resp=$(curl_json "${BASE_URL}" -H "Authorization: Bearer ${API_KEY}") || return 1
  printf '%s' "$resp" | jq -rc '
    if .success != true then empty
    else
      ((1 - (.data.quota_5_hour.usage_percentage // 0)) * 100) as $five_rem
      | ((1 - (.data.quota_7_day.usage_percentage // 0)) * 100) as $wk_rem
      | [
          (if .data.quota_5_hour.usage_percentage != null then "5h " + ($five_rem | floor | tostring) + "%" else empty end),
          (if .data.quota_7_day.usage_percentage  != null then "wk " + ($wk_rem  | floor | tostring) + "%" else empty end)
        ] | map(select(. != "")) | join(" · ")
    end
  ' 2>/dev/null
}

# ---- DeepSeek ----
# endpoint: https://api.deepseek.com/user/balance, Bearer
# response: {is_available, balance_infos: [{currency, total_balance, granted_balance, topped_up_balance}]}
# Output per non-zero currency: "¥ 12.34" or "$ 5.67"
fetch_deepseek() {
  local resp
  resp=$(curl_json "https://api.deepseek.com/user/balance" \
    -H "Authorization: Bearer ${API_KEY}") || return 1
  printf '%s' "$resp" | jq -rc '
    def fmt_amt:
      tostring as $s
      | (if $s | test("\\.") then $s else $s + ".00" end);
    def sym(c): if c == "CNY" or c == "¥" then "¥" elif c == "USD" or c == "$" then "$" else c end;
    [.balance_infos[]?
     | select((.total_balance // 0) | tonumber > 0)]
    | map("\(sym(.currency // "CNY")) \(.total_balance | fmt_amt)") | join(" / ")
  ' 2>/dev/null
}

# ---- Dispatch ----
out=""

# Base-URL exception: ZenMux (always show, regardless of model)
case "$BASE_URL" in
  *zenmux.ai*|*zenmux.com*) out=$(fetch_zenmux) ;;
esac

# If ZenMux matched, use that; otherwise dispatch by model
if [ -z "$out" ]; then
  case "$mlc" in
    *minimax*|*abab*)       out=$(fetch_minimax) ;;
    *kimi*|*moonshot*)      out=$(fetch_kimi) ;;
    *glm*)                  out=$(fetch_zhipu) ;;
    *deepseek*)             out=$(fetch_deepseek) ;;
  esac
fi

[ -z "$out" ] && exit 0

printf '%s' "$out" > "$CACHE"
printf '%s' "$out"
