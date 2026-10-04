#!/usr/bin/env bash
# Pretty wrapper around the CMake presets (dev / ci).
#
#   configure : cylon scanner sweeping across a neon track
#   build     : gradient progress bar with a liquid shimmer and a glowing
#               head, live file name, ETA and warning count
#   success   : short rainbow wave across the whole HUD
#   failure   : short red flicker, then the real error tail
#
# Nothing is hidden: full output always lands in build/<preset>/build.log,
# and failures print the real error tail. Plain output when piped or when
# NO_COLOR is set.
#
# Knobs (env):
#   NO_COLOR=1            plain output
#   TOTING_SIMPLE=1       the old single-line bar
#   TOTING_QUICK=1        skip the victory / failure flourish
#   TOTING_TRUECOLOR=0|1  force 256-colour / 24-bit colour
set -u

PRESET="${1:-dev}"
if [[ "$PRESET" != "dev" && "$PRESET" != "ci" ]]; then
    echo "usage: $(basename "$0") [dev|ci]" >&2
    exit 2
fi

cd "$(dirname "$0")/.." || exit 2

LOG="build/${PRESET}/build.log"
mkdir -p "build/${PRESET}"

# ───────────────────────── capability detection ─────────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    COLOR=1
else
    COLOR=0
fi

FANCY=0
COLS=80
ROWS=24
if ((COLOR)) && [[ -z "${TOTING_SIMPLE:-}" ]]; then
    COLS=$(tput cols 2>/dev/null || echo 80)
    ROWS=$(tput lines 2>/dev/null || echo 24)
    [[ "$COLS" =~ ^[0-9]+$ ]] || COLS=80
    [[ "$ROWS" =~ ^[0-9]+$ ]] || ROWS=24
    ((COLS >= 50 && ROWS >= 8)) && FANCY=1
fi

# 24-bit colour where we can trust it, 256-colour otherwise.
TC=0
case "${TOTING_TRUECOLOR:-auto}" in
    1) TC=1 ;;
    0) TC=0 ;;
    *)
        case "${COLORTERM:-}|${TERM_PROGRAM:-}|${TERM:-}" in
            *truecolor* | *24bit* | *iTerm* | *vscode* | *WezTerm* | *ghostty* | *kitty* | *alacritty* | *direct*) TC=1 ;;
        esac
        ;;
esac

if ((COLOR)); then
    BOLD=$'\e[1m'
    GREEN=$'\e[32m'
    RED=$'\e[31m'
    YELLOW=$'\e[33m'
    CYAN=$'\e[36m'
    DIM=$'\e[2m'
    WHITE=$'\e[97m'
    GRAY=$'\e[90m'
    RESET=$'\e[0m'
else
    BOLD=""
    GREEN=""
    RED=""
    YELLOW=""
    CYAN=""
    DIM=""
    WHITE=""
    GRAY=""
    RESET=""
fi

# ───────────────────────── shared parsing state ─────────────────────────
# Progress matchers live in variables (not inline-quoted): stock macOS
# bash 3.2 treats quoted regex metacharacters as literal text.
PROG_RE='\[([0-9]+)/([0-9]+)\](.*)$'
MAKE_RE='^\[ *([0-9]+)%\](.*)$'

DONE=0
TOTAL=0
DESC=""
WARNINGS=0
MUTED=0
SEEN=0
SHOWN=0
PID=""
CODE=0

# "Building CXX foo.o" -> "CXX foo.o"; sets DESC.
set_desc() {
    local rest="$1"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    rest="${rest#Building }"
    rest="${rest#Generating }"
    rest="${rest#Linking }"
    DESC="$rest"
}

# Parse one fresh log line: progress goes to the UI, warning blocks are
# counted quietly (details stay in the log), anything else passes through.
parse_line() {
    local line="$1"
    if [[ "$line" =~ $PROG_RE ]]; then
        MUTED=0
        DONE=$((10#${BASH_REMATCH[1]}))
        TOTAL=$((10#${BASH_REMATCH[2]}))
        set_desc "${BASH_REMATCH[3]}"
        ui_progress
    elif [[ "$line" =~ $MAKE_RE ]]; then # classic Makefile generator: [ 42%]
        MUTED=0
        DONE=$((10#${BASH_REMATCH[1]}))
        TOTAL=100
        set_desc "${BASH_REMATCH[2]}"
        ui_progress
    elif [[ -z "${line//[[:space:]]/}" ]]; then
        return 0
    elif [[ "$line" == *[Ww][Aa][Rr][Nn][Ii][Nn][Gg]* ]]; then
        WARNINGS=$((WARNINGS + 1))
        MUTED=1
    elif ((MUTED)); then
        return 0
    else
        ui_text "$line"
    fi
}

# Drain lines appended to $LOG since $SEEN (line count), updating SEEN.
# Plain read loop instead of mapfile: stock macOS bash is 3.2.
drain_log() {
    local line
    while IFS= read -r line; do
        SEEN=$((SEEN + 1))
        parse_line "$line"
    done < <(tail -n +"$((SEEN + 1))" "$LOG" 2>/dev/null)
}

ui_progress() {
    if ((FANCY)); then fx_progress; else simple_progress; fi
}
ui_text() {
    if ((FANCY)); then fx_text "$1"; else
        ((COLOR)) && printf "\n"
        printf "%s\n" "$1"
    fi
}

# ═══════════════════════════ SIMPLE MODE ════════════════════════════
# Single-line bar. Used for pipes, NO_COLOR, tiny terminals, TOTING_SIMPLE.
BAR_WIDTH=24
WORD="toting"
PALETTE=(34\;211\;238 42\;205\;239 51\;199\;240 59\;192\;241 67\;186\;241 75\;180\;242 84\;174\;243 92\;168\;244 100\;162\;245 108\;155\;246 117\;149\;247 125\;143\;248 133\;139\;248 142\;138\;248 151\;136\;248 160\;134\;248 169\;133\;248 178\;131\;248 187\;129\;249 196\;128\;249 205\;126\;249 214\;124\;249 223\;123\;249 232\;121\;249)

simple_progress() {
    if ((COLOR)); then render_bar; else printf "[%d/%d] %s\n" "$DONE" "$TOTAL" "$DESC"; fi
}

# SHOWN keeps the highest percent drawn so restated ninja totals never
# move the bar backwards.
render_bar() {
    local pct filled i bar
    if ((TOTAL > 0)); then pct=$((DONE * 100 / TOTAL)); else pct=0; fi
    ((pct < SHOWN)) && pct=$SHOWN
    SHOWN=$pct
    filled=$((pct * BAR_WIDTH / 100))
    bar=""
    for ((i = 0; i < filled; i++)); do bar+=$(printf '\e[38;2;%sm━' "${PALETTE[i]}"); done
    bar+="${DIM}"
    for ((i = filled; i < BAR_WIDTH; i++)); do bar+="─"; done
    bar+="${RESET}"
    printf "\r\e[K%s %s%3d%%%s" "$bar" "$BOLD" "$pct" "$RESET"
}

run_simple() {
    local START END spin word dots j
    START=$(date +%s)

    : >"$LOG"
    if ((COLOR)); then printf "%stoting%s " "$CYAN" "$RESET"; else echo "configuring..."; fi
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
    PID=""
    drain_log >/dev/null # keep offsets aligned; configure output stays in the log
    if ((CODE != 0)); then
        ((COLOR)) && printf "\r\e[K"
        printf "%sConfigure failed (exit %d). Last lines:%s\n" "$RED" "$CODE" "$RESET"
        tail -n 40 "$LOG"
        printf "%sFull log: %s%s\n" "$DIM" "$LOG" "$RESET"
        exit "$CODE"
    fi
    if ((COLOR)); then printf "\r\e[K%stoted%s\n" "$CYAN" "$RESET"; else echo "configured"; fi

    cmake --build --preset "$PRESET" >>"$LOG" 2>&1 &
    PID=$!
    while kill -0 "$PID" 2>/dev/null; do
        drain_log
        sleep 0.1
    done
    wait "$PID"
    CODE=$?
    PID=""
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
}

# ═══════════════════════════ FANCY MODE ═════════════════════════════
# A compact 3-line HUD drawn in place:
#
#   ◢◤ T O T I N G ◥◣ [dev]                      BUILDING 00:12
#   ▕██████████████▓▒░──────────────────────────▏  42%
#   ⠹ [47/112] src/module/file.cpp                   ETA 00:08
#
# Lag-proof by design: every colour escape is precomputed once at start-up,
# a frame is ~70 string appends (no maths-heavy loops, no forks), and it
# redraws at ~15 fps with only ~1 KB per frame.

fx_init() {
    local i idx r g b up

    W=$((COLS - 2))
    ((W > 72)) && W=72
    BW=$((W - 9))
    FH=3
    T=0
    EASE=0
    TARGET=0
    HUD_UP=0
    FROZEN=0
    ET=0
    BT=0
    BUILD_T0=0
    FIN=999
    printf -v UP '\e[%dA\r' "$FH"
    printf -v SP '%*s' 90 ''

    # palettes (r g b triples): cyan->indigo->fuchsia, and a rainbow wheel
    read -r -a NEON < <(awk 'BEGIN{
        n=4; split("34 211 238  120 150 247  232 121 249  120 150 247", c, " ")
        for(i=0;i<256;i++){ p=i*n/256; s=int(p); f=p-s; a=s%n; b=(s+1)%n
            for(k=1;k<=3;k++) printf "%d ", c[a*3+k]*(1-f)+c[b*3+k]*f } }')
    read -r -a RB < <(awk 'BEGIN{for(i=0;i<256;i++){a=i*6.2832/256
        printf "%d %d %d ", 128+127*sin(a), 128+127*sin(a+2.0944), 128+127*sin(a+4.1888)}}')

    if ((TC)); then
        TRACKFG=$'\e[38;2;52;56;84m'
        TRACKBG=$'\e[48;2;28;30;46m'
    else
        TRACKFG=$'\e[38;5;238m'
        TRACKBG=$'\e[48;5;235m'
    fi

    # bar gradient (normal + brightened) and rainbow, all precomputed
    BARFG=()
    BARHI=()
    for ((i = 0; i < BW; i++)); do
        idx=$((i * 128 / BW))
        r=${NEON[idx * 3]}; g=${NEON[idx * 3 + 1]}; b=${NEON[idx * 3 + 2]}
        mkfg "$r" "$g" "$b"
        BARFG[i]=$FG
        mkfg $((r + 60 > 255 ? 255 : r + 60)) $((g + 60 > 255 ? 255 : g + 60)) $((b + 60 > 255 ? 255 : b + 60))
        BARHI[i]=$FG
    done
    RBFG=()
    for ((i = 0; i < 256; i++)); do
        mkfg "${RB[i * 3]}" "${RB[i * 3 + 1]}" "${RB[i * 3 + 2]}"
        RBFG[i]=$FG
    done
    mkfg 255 70 70
    REDHI=$FG
    mkfg 150 30 40
    REDLO=$FG

    # cylon scanner glow levels (0 = head)
    CYL=()
    mkfg 255 255 255; CYL[0]="${FG}█"
    mkfg 34 211 238; CYL[1]="${FG}█"
    mkfg 70 170 244; CYL[2]="${FG}▓"
    mkfg 120 150 247; CYL[3]="${FG}▒"
    mkfg 180 130 249; CYL[4]="${FG}░"
    mkfg 232 121 249; CYL[5]="${FG}░"
    CYL[6]="${TRACKFG}─"

    # title letters
    up=$(tr '[:lower:]' '[:upper:]' <<<"$WORD")
    BRAND_SP=""
    for ((i = 0; i < ${#up}; i++)); do BRAND_SP+="${up:i:1} "; done
    BRAND_SP="${BRAND_SP% }"
    TN=${#BRAND_SP}
    TLC=()
    for ((i = 0; i < TN; i++)); do
        idx=$((i * 10))
        mkfg "${NEON[idx * 3]}" "${NEON[idx * 3 + 1]}" "${NEON[idx * 3 + 2]}"
        TLC[i]="${BOLD}${FG}"
    done
    mkfg 255 255 255
    TLW="${BOLD}${FG}"

    SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    EIGHTHS=("" ▏ ▎ ▍ ▌ ▋ ▊ ▉)
}

# mkfg R G B -> FG   (24-bit, or nearest 256-colour cube entry)
mkfg() {
    if ((TC)); then
        printf -v FG '\e[38;2;%d;%d;%dm' "$1" "$2" "$3"
    else
        printf -v FG '\e[38;5;%dm' $((16 + 36 * (($1 * 5 + 127) / 255) + 6 * (($2 * 5 + 127) / 255) + ($3 * 5 + 127) / 255))
    fi
}

# mode: cfg | build | ok | fail
fx_frame() {
    local mode=$1
    local i diff step out="" ps pos p dist fill8 filled frac sw k hp d
    local mw right ts vis pad title="" tc status cnt avail eta="" e r10 warn=""

    T=$((T + 1))
    ((FROZEN)) || {
        ET=$SECONDS
        BT=$((SECONDS - BUILD_T0))
    }

    # ease the displayed progress toward the real thing
    diff=$((TARGET * 100 - EASE))
    if ((diff > 0)); then
        step=$((diff / 4))
        ((step < 25)) && step=25
        ((step > diff)) && step=$diff
        EASE=$((EASE + step))
    fi

    # ── bar ──
    fill8=$((EASE * BW * 8 / 10000))
    filled=$((fill8 / 8))
    frac=$((fill8 % 8))
    case $mode in
        cfg)
            p=$((T % (2 * (BW - 1))))
            if ((p < BW)); then pos=$p; else pos=$((2 * (BW - 1) - p)); fi
            for ((i = 0; i < BW; i++)); do
                dist=$((i - pos))
                ((dist < 0)) && dist=$((-dist))
                ((dist > 6)) && dist=6
                out+=${CYL[dist]}
            done
            ps="scan"
            tc=$DIM$CYAN
            ;;
        build)
            sw=$(((T * 2) % (BW + 12) - 4)) # moving shimmer
            for ((i = 0; i < BW; i++)); do
                if ((i < filled)); then
                    k=$((i - sw))
                    if ((filled - i <= 2 || (k >= 0 && k < 3))); then out+="${BARHI[i]}█"; else out+="${BARFG[i]}█"; fi
                elif ((i == filled && frac > 0)); then
                    out+="${BARFG[i]}${TRACKBG}${EIGHTHS[frac]}${RESET}"
                else
                    out+="${TRACKFG}─"
                fi
            done
            printf -v ps '%3d%%' $((EASE / 100))
            k=$filled
            ((k >= BW)) && k=$((BW - 1))
            tc=$BOLD${BARFG[k]}
            ;;
        ok)
            for ((i = 0; i < BW; i++)); do out+="${RBFG[(i * 6 + T * 9) & 255]}█"; done
            ps="100%"
            tc=$BOLD${RBFG[(T * 9) & 255]}
            ;;
        fail)
            if ((FIN < 999 && FIN % 2)); then k=$REDHI; else k=$REDLO; fi
            for ((i = 0; i < BW; i++)); do
                if ((i < filled)); then out+="${k}█"; else out+="${TRACKFG}─"; fi
            done
            printf -v ps '%3d%%' $((EASE / 100))
            tc=$BOLD$REDHI
            ;;
    esac
    BAR=" ${GRAY}▕${out}${RESET}${GRAY}▏${RESET} ${tc}${ps}"

    # ── title ──
    hp=$(((T * 2) % (TN + 12) - 3))
    for ((i = 0; i < TN; i++)); do
        if [[ ${BRAND_SP:i:1} == " " ]]; then
            title+=" "
            continue
        fi
        d=$((i - hp))
        ((d < 0)) && d=$((-d))
        case $mode in
            ok) title+="${BOLD}${RBFG[(i * 20 + T * 9) & 255]}${BRAND_SP:i:1}" ;;
            fail) title+="${BOLD}${REDHI}${BRAND_SP:i:1}" ;;
            *) if ((d < 2)); then title+="${TLW}${BRAND_SP:i:1}"; else title+="${TLC[i]}${BRAND_SP:i:1}"; fi ;;
        esac
    done
    case $mode in
        cfg) mw="CONFIGURING" ;;
        build) mw="BUILDING" ;;
        ok) mw="DONE" ;;
        *) mw="FAILED" ;;
    esac
    printf -v ts '%02d:%02d' $((ET / 60)) $((ET % 60))
    right="$mw $ts"
    vis=$((TN + ${#PRESET} + 9))
    pad=$((W - vis - ${#right}))
    ((pad < 1)) && pad=1
    TITLE="${CYAN}◢◤ ${title}${RESET}${CYAN} ◥◣${RESET}${GRAY} [${PRESET}]${SP:0:pad}${right}"

    # ── status ──
    case $mode in
        ok)
            status=" ${GREEN}${BOLD}✔${RESET}${GREEN} built ${PRESET} in ${ET}s${GRAY} — ${TOTAL} steps, ${WARNINGS} warning(s)"
            ;;
        fail)
            status=" ${RED}${BOLD}✖ ${PRESET} failed (exit ${CODE})${RESET}${GRAY} — real error tail below"
            ;;
        *)
            if [[ $mode == build ]]; then
                cnt="[$DONE/$TOTAL] "
                e=$BT
                if ((e > 0 && DONE > 0 && TOTAL > DONE)); then
                    r10=$((e * (TOTAL - DONE) / DONE))
                    printf -v eta 'ETA %02d:%02d' $((r10 / 60)) $((r10 % 60))
                fi
            else
                cnt=""
            fi
            ((WARNINGS > 0)) && warn="warn ${WARNINGS}  "
            d=${DESC//$'\r'/}
            d=${d//$'\t'/ }
            if [[ -z $d ]]; then
                if [[ $mode == cfg ]]; then d="spinning up cmake"; else d="warming up"; fi
            fi
            avail=$((W - 4 - ${#cnt} - ${#eta} - ${#warn}))
            ((${#d} > avail)) && d="..${d: -$((avail - 2))}"
            pad=$((avail - ${#d}))
            ((pad < 1)) && pad=1
            status=" ${CYAN}${SPIN[T % 10]} ${GRAY}${cnt}${WHITE}${d}${RESET}${SP:0:pad}${YELLOW}${warn}${GRAY}${eta}"
            ;;
    esac

    FRAME=""
    ((HUD_UP)) && FRAME=$UP
    FRAME+="${RESET}"$'\e[?7l'" ${TITLE}${RESET}"$'\e[K\n'
    FRAME+="${BAR}${RESET}"$'\e[K\n'
    FRAME+="${status}${RESET}"$'\e[K\n'$'\e[?7h'
    printf '%s' "$FRAME"
    HUD_UP=1
}

# ─────────────────────────── hooks / lifecycle ─────────────────────────
fx_progress() {
    local pct=0
    ((TOTAL > 0)) && pct=$((DONE * 100 / TOTAL))
    ((pct < SHOWN)) && pct=$SHOWN
    SHOWN=$pct
    TARGET=$pct
}

# Compiler chatter etc. prints above the HUD, then the HUD redraws below.
fx_text() {
    if ((HUD_UP)); then
        printf '\e[%dA\r\e[J' "$FH"
        HUD_UP=0
    fi
    printf '%s\n' "$1"
}

# Latest configure output line becomes the status text.
fx_peek_cfg() {
    local l
    ((T % 5 == 0)) || return 0
    l=$(tail -n 1 "$LOG" 2>/dev/null)
    DESC=${l#-- }
}

fx_cleanup() {
    ((FANCY)) && printf '\e[0m\e[?25h\e[?7h'
    return 0
}

on_signal() {
    if [[ -n "$PID" ]]; then
        kill "$PID" 2>/dev/null
        pkill -P "$PID" 2>/dev/null
    fi
    ((FANCY)) && ((HUD_UP)) && printf '\n'
    printf '%sInterrupted.%s\n' "$YELLOW" "$RESET"
    exit 130
}

# Short victory: bar fills, then a rainbow wave sweeps the HUD (~0.5 s).
fx_finale_ok() {
    TARGET=100
    while ((EASE < 10000)); do
        fx_frame build
        sleep 0.05
    done
    FROZEN=1
    if [[ -z "${TOTING_QUICK:-}" ]]; then
        for ((FIN = 0; FIN < 12; FIN++)); do
            fx_frame ok
            sleep 0.04
        done
    fi
    FIN=999
    fx_frame ok
}

# Short failure: red flicker (~0.4 s), then the error tail.
fx_finale_fail() {
    FROZEN=1
    if [[ -z "${TOTING_QUICK:-}" ]]; then
        for ((FIN = 0; FIN < 8; FIN++)); do
            fx_frame fail
            sleep 0.05
        done
    fi
    FIN=999
    fx_frame fail
}

run_fancy() {
    fx_init
    trap fx_cleanup EXIT
    trap on_signal INT TERM
    printf '\e[?25l'
    SECONDS=0
    : >"$LOG"

    # ── configure: scanner ──
    cmake --preset "$PRESET" >>"$LOG" 2>&1 &
    PID=$!
    while kill -0 "$PID" 2>/dev/null; do
        fx_peek_cfg
        fx_frame cfg
        sleep 0.06
    done
    wait "$PID"
    CODE=$?
    PID=""
    SEEN=$(wc -l <"$LOG" | tr -d ' ')
    if ((CODE != 0)); then
        fx_finale_fail
        printf "%sConfigure failed (exit %d). Last lines:%s\n" "$RED" "$CODE" "$RESET"
        tail -n 40 "$LOG"
        printf "%sFull log: %s%s\n" "$DIM" "$LOG" "$RESET"
        exit "$CODE"
    fi
    DESC=""
    BUILD_T0=$SECONDS

    # ── build: gradient bar ──
    cmake --build --preset "$PRESET" >>"$LOG" 2>&1 &
    PID=$!
    while kill -0 "$PID" 2>/dev/null; do
        drain_log
        fx_frame build
        sleep 0.06
    done
    wait "$PID"
    CODE=$?
    PID=""
    drain_log

    if ((CODE != 0)); then
        fx_finale_fail
        printf "%sBuild %s failed (exit %d). Last lines:%s\n" "$RED" "$PRESET" "$CODE" "$RESET"
        tail -n 50 "$LOG"
        printf "%sFull log: %s%s\n" "$DIM" "$LOG" "$RESET"
        exit "$CODE"
    fi

    fx_finale_ok
    printf "%sBuild %s finished in %ds%s\n" "$GREEN" "$PRESET" "$ET" "$RESET"
    if ((WARNINGS > 0)); then
        printf "%s%d warning(s) — see %s%s\n" "$YELLOW" "$WARNINGS" "$LOG" "$RESET"
    fi
}

if ((FANCY)); then
    run_fancy
else
    run_simple
fi
