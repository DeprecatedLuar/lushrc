#!/usr/bin/env bash

CRONOTRIGGER_LOG_TIME_FORMAT='+%Y-%m-%dT%H:%M:%S%z'

cronotrigger_execute_body() {
    local name="$1" status

    printf '[%s] start %s\n' "$(date "$CRONOTRIGGER_LOG_TIME_FORMAT")" "$name"
    if (
        cd "$CRONOTRIGGER_EXECUTION_DIR" || exit 1
        "$CRONOTRIGGER_BASH_BIN" -c "$JOB_COMMAND"
    ); then
        status=0
    else
        status=$?
    fi
    printf '[%s] finish %s exit=%s\n' "$(date "$CRONOTRIGGER_LOG_TIME_FORMAT")" "$name" "$status"
    return "$status"
}

cronotrigger_run_job() {
    local name="$1" mode="$2" path log_path status

    cronotrigger_validate_name "$name" || return 1
    path="$(cronotrigger_job_path "$name")"
    [[ -f "$path" ]] || {
        echo "cronotrigger: job '$name' does not exist" >&2
        return 1
    }

    if [[ "$mode" == scheduled ]] && ! cronotrigger_is_enabled "$name"; then
        return 0
    fi

    cronotrigger_load_job "$path" || return 1
    cronotrigger_validate_job || {
        echo "cronotrigger: job '$name' is invalid" >&2
        return 1
    }

    if [[ "$mode" == scheduled ]] && ! cronotrigger_job_is_due; then
        return 0
    fi

    log_path="$CRONOTRIGGER_LOG_DIR/$name.log"
    if [[ "$mode" == manual ]]; then
        set +o pipefail
        cronotrigger_execute_body "$name" 2>&1 | tee -a "$log_path"
        status=${PIPESTATUS[0]}
        set -o pipefail
        return "$status"
    fi

    cronotrigger_execute_body "$name" >> "$log_path" 2>&1
}
