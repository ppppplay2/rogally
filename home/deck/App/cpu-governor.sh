#!/bin/bash
# 由 wrapper 通过 sudo 启动，以 root 身份运行
# 只做调频，游戏退出时由 wrapper 发 SIGTERM，本脚本 trap 恢复
set -euo pipefail

# ====================== 配置区 ======================
MIN_CPU_FREQ_KHZ=1400000
UTIL_TARGET=80
EWMA_HALF_LIFE_PERIODS=16
UTIL_CEILING=85
SAMPLE_INTERVAL=0.5
# ====================================================

if [[ $EUID -ne 0 ]]; then
    exit 1
fi

declare -A ORIG_MAX_FREQ
declare -a POLICY_PATHS
declare -a PREV_CPU_IDLE PREV_CPU_TOTAL CURR_CPU_LOAD
declare -A EWMA_UTIL
restored=0

compute_alpha() {
    local y alpha
    y=$(awk "BEGIN {printf \"%.10f\", 0.5^(1.0/$1)}")
    alpha=$(awk "BEGIN {printf \"%d\", (1.0-$y)*10000}")
    echo "$alpha"
}
ALPHA_X10000=$(compute_alpha "$EWMA_HALF_LIFE_PERIODS")

collect_policies() {
    POLICY_PATHS=()
    local p
    for p in /sys/devices/system/cpu/cpufreq/policy*/; do
        if [[ -d "$p" ]]; then
            POLICY_PATHS+=("${p%/}")
        fi
    done
    if [[ ${#POLICY_PATHS[@]} -eq 0 ]]; then
        exit 1
    fi
}

snapshot() {
    ORIG_MAX_FREQ=()
    local p v
    for p in "${POLICY_PATHS[@]}"; do
        if [[ -r "$p/scaling_max_freq" ]]; then
            ORIG_MAX_FREQ["$p"]=$(<"$p/scaling_max_freq")
        fi
    done
}

restore_snapshot() {
    local p v
    for p in "${!ORIG_MAX_FREQ[@]}"; do
        v=${ORIG_MAX_FREQ[$p]}
        if [[ -w "$p/scaling_max_freq" ]]; then
            echo "$v" > "$p/scaling_max_freq" 2>/dev/null || true
        fi
    done
}

cleanup() {
    if (( restored == 0 )); then
        restored=1
        restore_snapshot
    fi
    exit 0
}
trap cleanup EXIT INT TERM

set_all_max_freq() {
    local target=$1
    local p t minf min_v
    for p in "${POLICY_PATHS[@]}"; do
        if [[ ! -w "$p/scaling_max_freq" ]]; then
            continue
        fi
        t=$target
        minf="$p/scaling_min_freq"
        if [[ -r "$minf" ]]; then
            min_v=$(<"$minf")
            if (( t < min_v )); then
                t=$min_v
            fi
        fi
        echo "$t" > "$p/scaling_max_freq" 2>/dev/null || true
    done
}

parse_cpu_line() {
    local -a f
    read -ra f <<< "${1#* }"
    local idle=$(( ${f[3]:-0} + ${f[4]:-0} ))
    local total=0 i
    for i in 0 1 2 3 4 5 6 7; do
        total=$(( total + ${f[i]:-0} ))
    done
    echo "$idle $total"
}

init_cpu_stats() {
    PREV_CPU_IDLE=()
    PREV_CPU_TOTAL=()
    CURR_CPU_LOAD=()
    EWMA_UTIL=()
    local line idx rest idle total
    while IFS= read -r line; do
        if [[ "$line" =~ ^cpu([0-9]+)[[:space:]] ]]; then
            idx=${BASH_REMATCH[1]}
            rest="${line#* }"
            read -r idle total <<< "$(parse_cpu_line "cpu$idx $rest")"
            PREV_CPU_IDLE[idx]=$idle
            PREV_CPU_TOTAL[idx]=$total
            CURR_CPU_LOAD[idx]=0
            EWMA_UTIL[idx]=0
        fi
    done < /proc/stat
}

sample_cpu_load() {
    local line idx
    local -a new_idle=() new_total=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^cpu([0-9]+)[[:space:]] ]]; then
            idx=${BASH_REMATCH[1]}
            local rest="${line#* }"
            local idle total
            read -r idle total <<< "$(parse_cpu_line "cpu$idx $rest")"
            new_idle[idx]=$idle
            new_total[idx]=$total
        fi
    done < /proc/stat

    for idx in "${!new_total[@]}"; do
        local dt=$(( new_total[idx] - ${PREV_CPU_TOTAL[idx]:-0} ))
        local di=$(( new_idle[idx] - ${PREV_CPU_IDLE[idx]:-0} ))
        local inst=0
        if (( dt > 0 )); then
            inst=$(( (dt - di) * 100 / dt ))
        fi
        CURR_CPU_LOAD[idx]=$inst

        local prev=${EWMA_UTIL[idx]:-0}
        EWMA_UTIL[idx]=$(( (ALPHA_X10000 * inst + (10000 - ALPHA_X10000) * prev) / 10000 ))
        PREV_CPU_TOTAL[idx]=${new_total[idx]}
        PREV_CPU_IDLE[idx]=${new_idle[idx]}
    done
}

get_max_ewma_util() {
    local max=0 v
    for v in "${EWMA_UTIL[@]:-}"; do
        if (( v > max )); then
            max=$v
        fi
    done
    echo "$max"
}

# ---------- 启动 ----------
collect_policies
snapshot
init_cpu_stats

orig_max=0
for p in "${!ORIG_MAX_FREQ[@]}"; do
    v=${ORIG_MAX_FREQ[$p]}
    if (( v > orig_max )); then
        orig_max=$v
    fi
done
if (( orig_max == 0 )); then
    orig_max=$MIN_CPU_FREQ_KHZ
fi

while true; do
    sample_cpu_load
    util=$(get_max_ewma_util)

    current_freq=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null || echo "$orig_max")
    if (( current_freq <= 0 )); then
        current_freq=$orig_max
    fi

    if (( util >= UTIL_CEILING )); then
        target=$orig_max
    else
        target=$(( current_freq * util / UTIL_TARGET ))
        if (( target < MIN_CPU_FREQ_KHZ )); then
            target=$MIN_CPU_FREQ_KHZ
        fi
        if (( target > orig_max )); then
            target=$orig_max
        fi
    fi

    cur=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2>/dev/null || echo 0)
    diff=$(( target - cur ))
    if (( diff < 0 )); then
        diff=$(( -diff ))
    fi
    if (( diff > orig_max / 100 )); then
        set_all_max_freq "$target"
    fi

    sleep "$SAMPLE_INTERVAL"
done
