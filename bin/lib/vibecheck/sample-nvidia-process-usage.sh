#!/usr/bin/env bash

PROGRAM_NAME="$(basename "$0")"
PROC_ROOT="/proc"
EXPECTED_ARGUMENT_COUNT=1
PERCENT_TENTHS_MULTIPLIER=10

fail() {
    printf '%s: %s\n' "$PROGRAM_NAME" "$1" >&2
    exit 1
}

is_counter() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

read_process_name() {
    local pid="$1"
    local fallback_name="$2"
    local process_name=""

    if [[ -r "$PROC_ROOT/$pid/cmdline" ]]; then
        IFS= read -r -d '' process_name < "$PROC_ROOT/$pid/cmdline" || true
        process_name="${process_name##*/}"
    fi
    if [[ -z "$process_name" ]] \
        && ! IFS= read -r process_name < "$PROC_ROOT/$pid/comm"; then
        process_name="$fallback_name"
    fi
    process_name="${process_name//$'\t'/ }"
    process_name="${process_name//$'\e'/?}"
    printf '%s\n' "$process_name"
}

(($# == EXPECTED_ARGUMENT_COUNT)) \
    || fail "usage: $PROGRAM_NAME GPU_INDEX"
gpu_index="$1"
is_counter "$gpu_index" || fail "invalid GPU index"
command -v nvidia-smi &>/dev/null || fail "nvidia-smi is not installed"

if ! pmon_output=$(nvidia-smi pmon -i "$gpu_index" -c 1 -s u 2>/dev/null); then
    fail "could not sample NVIDIA process usage"
fi

while read -r row_gpu pid process_type sm memory encoder decoder jpeg ofa fallback_name remainder; do
    is_counter "$row_gpu" || continue
    is_counter "$pid" || continue

    highest_usage=0
    for activity in "$sm" "$encoder" "$decoder" "$jpeg" "$ofa"; do
        is_counter "$activity" || continue
        ((activity > highest_usage)) && highest_usage="$activity"
    done
    ((highest_usage > 0)) || continue

    process_name=$(read_process_name "$pid" "$fallback_name")
    printf 'process %d %d %s\n' \
        "$pid" "$((highest_usage * PERCENT_TENTHS_MULTIPLIER))" "$process_name"
done <<< "$pmon_output"
