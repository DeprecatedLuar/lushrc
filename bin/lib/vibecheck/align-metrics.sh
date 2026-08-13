#!/usr/bin/env bash

DIM_STYLE=""
RESET_STYLE=""
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    DIM_STYLE=$'\e[2m'
    RESET_STYLE=$'\e[0m'
fi

awk -v dim_style="$DIM_STYLE" -v reset_style="$RESET_STYLE" '
    {
        lines[NR] = $0
        if (match($0, /^[^[:space:]]+/)) {
            label_length = RLENGTH
            labels[NR] = substr($0, RSTART, label_length)
            values[NR] = substr($0, label_length + 1)
            sub(/^[[:space:]]+/, "", values[NR])
            main_values[NR] = values[NR]
            if (match(values[NR], /[[:space:]]/)) {
                main_values[NR] = substr(values[NR], 1, RSTART - 1)
                details[NR] = substr(values[NR], RSTART)
                sub(/^[[:space:]]+/, "", details[NR])
            }
            if (label_length > label_width) {
                label_width = label_length
            }
            if (length(main_values[NR]) > value_width) {
                value_width = length(main_values[NR])
            }
        }
    }
    END {
        for (line_number = 1; line_number <= NR; line_number++) {
            if (labels[line_number] == "") {
                print lines[line_number]
            } else {
                printf "%-*s ", label_width, labels[line_number]
                if (details[line_number] != "") {
                    printf "%-*s %s%s%s", value_width, main_values[line_number], \
                        dim_style, details[line_number], reset_style
                } else {
                    printf "%s", main_values[line_number]
                }
                printf "\n"
            }
        }
    }
'
