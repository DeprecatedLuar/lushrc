#!/usr/bin/env bash

CRONOTRIGGER_TIME_PATTERN='^([01][0-9]|2[0-3]):([0-5][0-9])$'
CRONOTRIGGER_ANCHOR_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]$'
CRONOTRIGGER_MAX_INTERVAL=1000000

cronotrigger_parse_time() {
    local value="$1"

    if [[ ! "$value" =~ $CRONOTRIGGER_TIME_PATTERN ]]; then
        echo "cronotrigger: time '$value' must use HH:MM in 24-hour format" >&2
        return 1
    fi

    SCHEDULE_HOUR="${BASH_REMATCH[1]}"
    SCHEDULE_MINUTE="${BASH_REMATCH[2]}"
}

cronotrigger_ordinal_number() {
    local token="$1" number suffix expected

    if [[ ! "$token" =~ ^([1-9]|[12][0-9]|3[01])(st|nd|rd|th)$ ]]; then
        return 1
    fi

    number="${BASH_REMATCH[1]}"
    suffix="${BASH_REMATCH[2]}"
    case "$number" in
        11|12|13) expected=th ;;
        *1) expected=st ;;
        *2) expected=nd ;;
        *3) expected=rd ;;
        *) expected=th ;;
    esac

    [[ "$suffix" == "$expected" ]] || return 1
    printf '%s\n' "$number"
}

cronotrigger_parse_schedule() {
    local every token number weekday_number seen="," interval interval_text
    local -a tokens=() values=()

    SCHEDULE_MODE=""
    SCHEDULE_INTERVAL=""
    SCHEDULE_CRON_DAYS=""
    SCHEDULE_HOUR=""
    SCHEDULE_MINUTE=""
    every="${JOB_EVERY,,}"
    every="${every//[[:space:]]/}"

    case "$every" in
        day|d|1d)
            SCHEDULE_MODE=day
            ;;
        hour|h|1h)
            SCHEDULE_MODE=hour_interval
            SCHEDULE_INTERVAL=1
            ;;
        *)
            if [[ "$every" =~ ^([1-9][0-9]*)d$ ]]; then
                interval_text="${BASH_REMATCH[1]}"
                if ((${#interval_text} > ${#CRONOTRIGGER_MAX_INTERVAL})); then
                    echo "cronotrigger: day interval exceeds $CRONOTRIGGER_MAX_INTERVAL" >&2
                    return 1
                fi
                interval=$((10#$interval_text))
                ((interval <= CRONOTRIGGER_MAX_INTERVAL)) || {
                    echo "cronotrigger: day interval exceeds $CRONOTRIGGER_MAX_INTERVAL" >&2
                    return 1
                }
                SCHEDULE_MODE=day_interval
                SCHEDULE_INTERVAL="$interval"
            elif [[ "$every" =~ ^([1-9][0-9]*)h$ ]]; then
                interval_text="${BASH_REMATCH[1]}"
                if ((${#interval_text} > ${#CRONOTRIGGER_MAX_INTERVAL})); then
                    echo "cronotrigger: hour interval exceeds $CRONOTRIGGER_MAX_INTERVAL" >&2
                    return 1
                fi
                interval=$((10#$interval_text))
                ((interval <= CRONOTRIGGER_MAX_INTERVAL)) || {
                    echo "cronotrigger: hour interval exceeds $CRONOTRIGGER_MAX_INTERVAL" >&2
                    return 1
                }
                SCHEDULE_MODE=hour_interval
                SCHEDULE_INTERVAL="$interval"
            else
                IFS=',' read -r -a tokens <<< "$every"
                ((${#tokens[@]} > 0)) || {
                    echo "cronotrigger: every is required" >&2
                    return 1
                }

                for token in "${tokens[@]}"; do
                    case "$token" in
                        sun) weekday_number=0 ;;
                        mon) weekday_number=1 ;;
                        tue) weekday_number=2 ;;
                        wed) weekday_number=3 ;;
                        thu) weekday_number=4 ;;
                        fri) weekday_number=5 ;;
                        sat) weekday_number=6 ;;
                        *) weekday_number="" ;;
                    esac

                    if [[ -n "$weekday_number" ]]; then
                        [[ "$SCHEDULE_MODE" != month_days ]] || {
                            echo "cronotrigger: every cannot mix weekdays and month days" >&2
                            return 1
                        }
                        SCHEDULE_MODE=weekdays
                        number="$weekday_number"
                    elif number="$(cronotrigger_ordinal_number "$token")"; then
                        [[ "$SCHEDULE_MODE" != weekdays ]] || {
                            echo "cronotrigger: every cannot mix weekdays and month days" >&2
                            return 1
                        }
                        SCHEDULE_MODE=month_days
                    else
                        echo "cronotrigger: invalid every value '$JOB_EVERY'" >&2
                        return 1
                    fi

                    if [[ "$seen" == *",$number,"* ]]; then
                        echo "cronotrigger: duplicate schedule value '$token'" >&2
                        return 1
                    fi
                    seen+="$number,"
                    values+=("$number")
                done

                SCHEDULE_CRON_DAYS=$(IFS=,; printf '%s' "${values[*]}")
            fi
            ;;
    esac

    case "$SCHEDULE_MODE" in
        hour_interval)
            if [[ -n "$JOB_TIME" ]]; then
                echo "cronotrigger: time is not allowed with '$JOB_EVERY'" >&2
                return 1
            fi
            ;;
        *)
            [[ -n "$JOB_TIME" ]] || {
                echo "cronotrigger: time is required with '$JOB_EVERY'" >&2
                return 1
            }
            cronotrigger_parse_time "$JOB_TIME" || return 1
            ;;
    esac
}

cronotrigger_now() {
    if [[ -n "${CRONOTRIGGER_NOW:-}" ]]; then
        printf '%s\n' "$CRONOTRIGGER_NOW"
    else
        date '+%Y-%m-%dT%H:%M'
    fi
}

cronotrigger_date_add() {
    local value="$1" amount="$2" unit="$3" format gnu_value

    case "$unit" in
        day) format='+%Y-%m-%d' ;;
        hour) format='+%Y-%m-%dT%H:%M' ;;
        *) echo "cronotrigger: unsupported date unit '$unit'" >&2; return 1 ;;
    esac

    gnu_value="${value/T/ }"
    if date -d "$gnu_value $amount $unit" "$format" 2>/dev/null; then
        return 0
    fi

    case "$unit" in
        day)
            date -j -f '%Y-%m-%d' "$value" -v+"${amount}"d "$format" 2>/dev/null
            ;;
        hour)
            date -j -f '%Y-%m-%dT%H:%M' "$value" -v+"${amount}"H "$format" 2>/dev/null
            ;;
    esac || {
        echo "cronotrigger: local date command cannot calculate schedule anchors" >&2
        return 1
    }
}

cronotrigger_generate_anchor() {
    local now today now_time first_date

    now="$(cronotrigger_now)"
    [[ "$now" =~ $CRONOTRIGGER_ANCHOR_PATTERN ]] || {
        echo "cronotrigger: current time '$now' is invalid" >&2
        return 1
    }

    case "$SCHEDULE_MODE" in
        day_interval)
            today="${now%%T*}"
            now_time="${now#*T}"
            if [[ "$now_time" < "$JOB_TIME" ]]; then
                first_date="$today"
            else
                first_date="$(cronotrigger_date_add "$today" 1 day)" || return 1
            fi
            JOB_ANCHOR="${first_date}T${JOB_TIME}"
            ;;
        hour_interval)
            JOB_ANCHOR="$(cronotrigger_date_add "$now" "$SCHEDULE_INTERVAL" hour)" || return 1
            ;;
        *)
            JOB_ANCHOR=""
            ;;
    esac
}

cronotrigger_validate_anchor() {
    local canonical

    [[ "$JOB_ANCHOR" =~ $CRONOTRIGGER_ANCHOR_PATTERN ]] || {
        echo "cronotrigger: anchor '$JOB_ANCHOR' must use YYYY-MM-DDTHH:MM" >&2
        return 1
    }

    canonical=$(cronotrigger_date_add "$JOB_ANCHOR" 0 hour) || return 1
    [[ "$canonical" == "$JOB_ANCHOR" ]] || {
        echo "cronotrigger: anchor '$JOB_ANCHOR' is not a valid local date" >&2
        return 1
    }
}

cronotrigger_validate_job() {
    cronotrigger_parse_schedule || return 1

    [[ -n "$JOB_COMMAND" ]] || {
        echo "cronotrigger: command is required" >&2
        return 1
    }
    case "$SCHEDULE_MODE" in
        day_interval|hour_interval)
            cronotrigger_validate_anchor || return 1
            ;;
        *)
            [[ -z "$JOB_ANCHOR" ]] || {
                echo "cronotrigger: anchor is only valid for Nd and Nh schedules" >&2
                return 1
            }
            ;;
    esac
}

cronotrigger_finalize_job() {
    local regenerate_anchor="$1"

    cronotrigger_parse_schedule || return 1
    if [[ "$SCHEDULE_MODE" == day_interval || "$SCHEDULE_MODE" == hour_interval ]]; then
        if [[ "$regenerate_anchor" == true || -z "$JOB_ANCHOR" ]]; then
            cronotrigger_generate_anchor || return 1
        fi
    else
        JOB_ANCHOR=""
    fi
    cronotrigger_validate_job
}

cronotrigger_compile_schedule() {
    cronotrigger_parse_schedule || return 1

    case "$SCHEDULE_MODE" in
        day|day_interval)
            CRON_SPEC="$((10#$SCHEDULE_MINUTE)) $((10#$SCHEDULE_HOUR)) * * *"
            ;;
        weekdays)
            CRON_SPEC="$((10#$SCHEDULE_MINUTE)) $((10#$SCHEDULE_HOUR)) * * $SCHEDULE_CRON_DAYS"
            ;;
        month_days)
            CRON_SPEC="$((10#$SCHEDULE_MINUTE)) $((10#$SCHEDULE_HOUR)) $SCHEDULE_CRON_DAYS * *"
            ;;
        hour_interval)
            CRON_SPEC="$((10#${JOB_ANCHOR:14:2})) * * * *"
            ;;
    esac
}

cronotrigger_date_ordinal() {
    local value="$1" year month day adjusted_year era year_of_era adjusted_month
    local day_of_year day_of_era

    IFS=- read -r year month day <<< "$value"
    year=$((10#$year))
    month=$((10#$month))
    day=$((10#$day))
    adjusted_year="$year"
    ((month <= 2)) && adjusted_year=$((adjusted_year - 1))
    era=$((adjusted_year / 400))
    year_of_era=$((adjusted_year - era * 400))
    if ((month > 2)); then
        adjusted_month=$((month - 3))
    else
        adjusted_month=$((month + 9))
    fi
    day_of_year=$(((153 * adjusted_month + 2) / 5 + day - 1))
    day_of_era=$((year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year))
    printf '%s\n' "$((era * 146097 + day_of_era))"
}

cronotrigger_job_is_due() {
    local now anchor_date now_date anchor_ordinal now_ordinal delta
    local anchor_hour now_hour

    cronotrigger_parse_schedule || return 1
    case "$SCHEDULE_MODE" in
        day_interval)
            now="$(cronotrigger_now)"
            anchor_date="${JOB_ANCHOR%%T*}"
            now_date="${now%%T*}"
            anchor_ordinal="$(cronotrigger_date_ordinal "$anchor_date")"
            now_ordinal="$(cronotrigger_date_ordinal "$now_date")"
            delta=$((now_ordinal - anchor_ordinal))
            ((delta >= 0 && delta % SCHEDULE_INTERVAL == 0))
            ;;
        hour_interval)
            now="$(cronotrigger_now)"
            anchor_ordinal="$(cronotrigger_date_ordinal "${JOB_ANCHOR%%T*}")"
            now_ordinal="$(cronotrigger_date_ordinal "${now%%T*}")"
            anchor_hour=$((10#${JOB_ANCHOR:11:2}))
            now_hour=$((10#${now:11:2}))
            delta=$(((now_ordinal - anchor_ordinal) * 24 + now_hour - anchor_hour))
            ((delta >= 0 && delta % SCHEDULE_INTERVAL == 0))
            ;;
        *)
            return 0
            ;;
    esac
}

cronotrigger_schedule_description() {
    if [[ "$SCHEDULE_MODE" == hour_interval ]]; then
        printf 'every %s\n' "$JOB_EVERY"
    else
        printf '%s at %s\n' "$JOB_EVERY" "$JOB_TIME"
    fi
}
