#!/usr/bin/env bash
# Pretty wrapper around the CMake presets (dev / ci).
# Shows a single-line colorful progress bar while building and a spinner
# while configuring. Nothing is hidden: full output always lands in
# build/<preset>/build.log, and failures print the real error tail.
# Plain output when piped or when NO_COLOR is set.
set -u

PRESET="${1:-dev}"
if [[ "$PRESET" != "dev" && "$PRESET" != "ci" ]]; then
    echo "usage: $(basename "$0") [dev|ci]" >&2
    exit 2
fi

cd "$(dirname "$0")/.." || exit 2

LOG="build/${PRESET}/build.log"
mkdir -p "build/${PRESET}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    COLOR=1
else
    COLOR=0
fi
if ((COLOR)); then
    BOLD=$'\e[1m'
    GREEN=$'\e[32m'
    RED=$'\e[31m'
    YELLOW=$'\e[33m'
    CYAN=$'\e[36m'
    DIM=$'\e[2m'
    RESET=$'\e[0m'
else
    BOLD=""
    GREEN=""
    RED=""
    YELLOW=""
    CYAN=""
    DIM=""
    RESET=""
fi

BAR_WIDTH=24
WORD="toting"
# Cyan -> indigo -> fuchsia across the fill.
PALETTE=(34\;211\;238 42\;205\;239 51\;199\;240 59\;192\;241 67\;186\;241 75\;180\;242 84\;174\;243 92\;168\;244 100\;162\;245 108\;155\;246 117\;149\;247 125\;143\;248 133\;139\;248 142\;138\;248 151\;136\;248 160\;134\;248 169\;133\;248 178\;131\;248 187\;129\;249 196\;128\;249 205\;126\;249 214\;124\;249 223\;123\;249 232\;121\;249)

# Render one progress line. Globals set by parse_line: DONE, TOTAL, DESC.
# SHOWN keeps the highest percent drawn so restated ninja totals never
# move the bar backwards.
SHOWN=0
render_bar() {
    local pct filled empty i bar
    if ((TOTAL > 0)); then
        pct=$((DONE * 100 / TOTAL))
    else
        pct=0
    fi
    ((pct < SHOWN)) && pct=$SHOWN
    SHOWN=$pct
    filled=$((pct * BAR_WIDTH / 100))
    bar=""
    if ((COLOR)); then
        for ((i = 0; i < filled; i++)); do bar+=$(printf '\e[38;2;%sm━' "${PALETTE[i]}"); done
        bar+="${DIM}"
        for ((i = filled; i < BAR_WIDTH; i++)); do bar+="─"; done
        bar+="${RESET}"
    else
        for ((i = 0; i < filled; i++)); do bar+="█"; done
        for ((i = filled; i < BAR_WIDTH; i++)); do bar+="░"; done
    fi
    if ((COLOR)); then
        printf "\r\e[K%s %s%3d%%%s" \
            "$bar" "$BOLD" "$pct" "$RESET"
    else
        printf "[%d/%d] %s\n" "$DONE" "$TOTAL" "$DESC"
    fi
}

# Progress matcher lives in a variable (not inline-quoted): stock macOS
# bash 3.2 treats quoted regex metacharacters as literal text.
PROG_RE='\[([0-9]+)/([0-9]+)\](.*)$'

# Parse one fresh log line: progress redraws the bar, warning blocks are
# counted quietly (details stay in the log), anything else passes through.
DONE=0
TOTAL=0
DESC=""
WARNINGS=0
MUTED=0
parse_line() {
    local line="$1" n m rest
    if [[ "$line" =~ $PROG_RE ]]; then
        MUTED=0
        n="${BASH_REMATCH[1]}"
        m="${BASH_REMATCH[2]}"
        rest="${BASH_REMATCH[3]}"
        DONE="$n"
        TOTAL="$m"
        # Drop the "[x/y] action target" prefix down to the file path.
        rest="${rest#"${rest%%[![:space:]]*}"}"
        rest="${rest#Building }"
        rest="${rest#Generating }"
        rest="${rest#Linking }"
        DESC="$rest"
        if ((COLOR)); then
            render_bar
        else
            printf "[%d/%d] %s\n" "$DONE" "$TOTAL" "$DESC"
        fi
    elif [[ -z "${line//[[:space:]]/}" ]]; then
        return 0
    elif [[ "$line" == *[Ww][Aa][Rr][Nn][Ii][Nn][Gg]* ]]; then
        WARNINGS=$((WARNINGS + 1))
        MUTED=1
    elif ((MUTED)); then
        return 0
    else
        ((COLOR)) && printf "\n"
        printf "%s\n" "$line"
    fi
}

# Drain lines appended to $LOG since $SEEN (line count), updating SEEN.
# Plain read loop instead of mapfile: stock macOS bash is 3.2.
SEEN=0
drain_log() {
    local line
    while IFS= read -r line; do
        SEEN=$((SEEN + 1))
        parse_line "$line"
    done < <(tail -n +"$((SEEN + 1))" "$LOG" 2>/dev/null)
}

START=$(date +%s)

# --- configure (toting animation; no parseable progress) ---
: >"$LOG"
printf "%stoting%s " "$CYAN" "$RESET"
cmake --preset "$PRESET" >>"$LOG" 2>&1 &
PID=$!
spin=0
while kill -0 "$PID" 2>/dev/null; do
    if ((COLOR)); then
        word=""
        for ((j = 0; j < 6; j++)); do
            word+=$(printf '\e[38;2;%sm%s' "${PALETTE[$(((spin * 2 + j) % BAR_WIDTH))]}" "${WORD:j:1}")
        done
        dots=""
        case $((spin % 4)) in
            1) dots="." ;;
            2) dots=".." ;;
            3) dots="..." ;;
        esac
        printf "\r%s%s%-3s%s" "$word" "$DIM" "$dots" "$RESET"
        spin=$((spin + 1))
    fi
    sleep 0.15
done
wait "$PID"
CODE=$?
drain_log >/dev/null # keep offsets aligned; configure output stays in the log
if ((CODE != 0)); then
    printf "\r\e[K%sConfigure failed (exit %d). Last lines:%s\n" "$RED" "$CODE" "$RESET"
    tail -n 40 "$LOG"
    printf "%sFull log: %s%s\n" "$DIM" "$LOG" "$RESET"
    exit "$CODE"
fi
printf "\r\e[K%stoted%s\n" "$CYAN" "$RESET"

# --- build (progress bar, errors surface from the log) ---
cmake --build --preset "$PRESET" >>"$LOG" 2>&1 &
PID=$!
while kill -0 "$PID" 2>/dev/null; do
    drain_log
    sleep 0.1
done
wait "$PID"
CODE=$?
drain_log

if ((CODE != 0)); then
    ((COLOR)) && printf "\n"
    printf "%sBuild %s failed (exit %d). Last lines:%s\n" "$RED" "$PRESET" "$CODE" "$RESET"
    tail -n 50 "$LOG"
    printf "%sFull log: %s%s\n" "$DIM" "$LOG" "$RESET"
    exit "$CODE"
fi

END=$(date +%s)
((COLOR)) && printf "\n"
printf "%sBuild %s finished in %ds%s\n" "$GREEN" "$PRESET" "$((END - START))" "$RESET"
if ((WARNINGS > 0)); then
    printf "%s%d warning(s) — see %s%s\n" "$YELLOW" "$WARNINGS" "$LOG" "$RESET"
fi
