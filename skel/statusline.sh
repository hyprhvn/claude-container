#!/usr/bin/env bash
# Claude Code status line
# Shows: user@host  dir(git-branch)  |  model  |  context remaining  |  session tokens  |  est. cost
#
# Token totals are summed from the session transcript (each assistant
# message's usage, i.e. what the provider actually bills per API call).
# Cost is estimated from live OpenRouter pricing (cached for 1h in
# ~/.cache/claude-statusline/). Tiered "overrides" pricing is not applied;
# the base rate is used, so treat the cost as a rough estimate.
set -o pipefail

CACHE_DIR="${HOME}/.cache/claude-statusline"
CACHE_FILE="$CACHE_DIR/openrouter-pricing.json"
CACHE_TTL=3600

input=$(cat)

# ---------- stdin JSON ----------
model_id=$(printf '%s' "$input" | jq -r '.model.id // empty')
model_name=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

# ---------- user@host ----------
userhost="$(whoami 2>/dev/null)@$(hostname -s 2>/dev/null)"

# ---------- directory (with ~) ----------
dir="${cwd/#$HOME/~}"
[ -n "$dir" ] || dir="?"

# ---------- git branch ----------
branch=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
	branch=$(git -C "$cwd" symbolic-ref --short -q HEAD || git -C "$cwd" rev-parse --short HEAD 2>/dev/null || true)
fi

# ---------- OpenRouter pricing (1h cache) ----------
mkdir -p "$CACHE_DIR" 2>/dev/null
now=$(date +%s)
mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
if [ ! -f "$CACHE_FILE" ] || [ $((now - mtime)) -gt "$CACHE_TTL" ]; then
	tmp=$(mktemp 2>/dev/null) && {
		if curl -fsS --max-time 6 'https://openrouter.ai/api/v1/models' -o "$tmp" 2>/dev/null &&
			jq -e . "$tmp" >/dev/null 2>&1; then
			mv "$tmp" "$CACHE_FILE"
		else
			rm -f "$tmp"
		fi
	}
fi

# Model id in the session may carry a variant suffix, e.g. qwen/qwen3.8-27b[1m]
# while OpenRouter lists the base id qwen/qwen3.8-27b. Try exact, then strip suffixes.
find_model() {
	[ -f "$CACHE_FILE" ] || return 1
	jq -c --arg id "$1" '.data[] | select(.id == $id)' "$CACHE_FILE" 2>/dev/null | head -1
}
entry=$(find_model "$model_id")
if [ -z "$entry" ] && [[ "$model_id" == *[* ]]; then
	entry=$(find_model "${model_id%%[[]*}")
fi
if [ -z "$entry" ] && [[ "$model_id" == *:* ]]; then
	entry=$(find_model "${model_id%%:*}")
fi
if [ -z "$entry" ] && [[ "$model_id" == *[*:* ]]; then
	base="${model_id%%[[]*}"
	base="${base%%:*}"
	entry=$(find_model "$base")
fi

ctx_len=0
p_prompt=0
p_completion=0
p_cache_read=""
p_cache_write=""
if [ -n "$entry" ]; then
	ctx_len=$(printf '%s' "$entry" | jq -r '.context_length // 0')
	p_prompt=$(printf '%s' "$entry" | jq -r '.pricing.prompt // 0')
	p_completion=$(printf '%s' "$entry" | jq -r '.pricing.completion // 0')
	p_cache_read=$(printf '%s' "$entry" | jq -r '.pricing.input_cache_read // empty')
	p_cache_write=$(printf '%s' "$entry" | jq -r '.pricing.input_cache_write // empty')
fi

# ---------- session token totals from transcript ----------
tot_in=0
tot_cc=0
tot_cr=0
tot_out=0
last_ctx=0
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
	while IFS=' ' read -r tot_in tot_cc tot_cr tot_out last_ctx; do
		break
	done < <(jq -rs '
    [ .[]? | select(.type? == "assistant") | .message.usage? // empty ] as $u
    | ( $u | map(.input_tokens // 0)               | add // 0 ) as $i
    | ( $u | map(.cache_creation_input_tokens // 0) | add // 0 ) as $cc
    | ( $u | map(.cache_read_input_tokens // 0)     | add // 0 ) as $cr
    | ( $u | map(.output_tokens // 0)               | add // 0 ) as $o
    | ( ($u | last) as $l
        | if $l == null then 0
          else ($l.input_tokens // 0) + ($l.cache_creation_input_tokens // 0) + ($l.cache_read_input_tokens // 0)
          end ) as $lc
    | "\($i) \($cc) \($cr) \($o) \($lc)"
  ' "$transcript" 2>/dev/null)
fi
tot_in=${tot_in:-0}
tot_cc=${tot_cc:-0}
tot_cr=${tot_cr:-0}
tot_out=${tot_out:-0}
last_ctx=${last_ctx:-0}

# ---------- cost estimate ----------
fmt_tokens() {
	awk -v n="$1" 'BEGIN{
    if (n >= 1000000)      printf "%.2fM", n/1000000
    else if (n >= 1000)    printf "%.1fk", n/1000
    else                   printf "%d", n
  }'
}
cost_str=""
if [ -n "$entry" ]; then
	cost=$(awk -v i="$tot_in" -v cc="$tot_cc" -v cr="$tot_cr" -v o="$tot_out" \
		-v pp="$p_prompt" -v pc="$p_completion" -v prc="$p_cache_read" -v pcw="$p_cache_write" 'BEGIN{
      if (prc == "") prc = pp * 0.1   # fallback: ~10% of prompt rate
      if (pcw == "") pcw = pp * 1.25  # fallback: ~125% of prompt rate
      c = i*pp + cr*prc + cc*pcw + o*pc
      if (c >= 1)       printf "$%.2f", c
      else if (c >= 0.01) printf "$%.3f", c
      else                printf "$%.4f", c
    }')
	cost_str="$cost"
fi

# ---------- context remaining ----------
ctx_str=""
ctx_pct=0
if [ "${ctx_len:-0}" -gt 0 ] 2>/dev/null && [ "$last_ctx" -gt 0 ] 2>/dev/null; then
	ctx_pct=$(awk -v used="$last_ctx" -v len="$ctx_len" 'BEGIN{ r=(len-used)/len*100; if (r<0) r=0; printf "%d", r }')
	ctx_str="ctx ${ctx_pct}%"
fi

# ---------- assemble ----------
reset=$'\033[0m'
dim=$'\033[2m'
bold=$'\033[1m'
cyan=$'\033[36m'
blue=$'\033[34m'
magenta=$'\033[35m'
yellow=$'\033[33m'
green=$'\033[32m'
red=$'\033[31m'
orange=$'\033[38;5;208m'

sep=$'  '"$dim"'|'$reset
out="${bold}${cyan}${userhost}${reset} ${bold}${blue}${dir}${reset}"
[ -n "$branch" ] && out+=" ${magenta}(${branch})${reset}"

model_disp="${model_name:-$model_id}"
[ -n "$model_disp" ] && out+="$sep ${yellow}${model_disp}${reset}"

if [ -n "$ctx_str" ]; then
	if [ "$ctx_pct" -le 10 ]; then
		cctx="$red"
	elif [ "$ctx_pct" -le 20 ]; then
		cctx="$orange"
	else
		cctx="$green"
	fi
	out+="$sep ${cctx}${ctx_str}${reset}"
fi

out+="$sep ${dim}$(fmt_tokens $((tot_in + tot_cc + tot_cr + tot_out))) tok${reset}"

if [ -n "$cost_str" ]; then
	out+="$sep ${green}${cost_str}${reset} ${dim}est${reset}"
else
	out+="$sep ${dim}cost n/a${reset}"
fi

printf '%s' "$out"
