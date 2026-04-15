#!/usr/bin/env bash

metrics=("$@")
[[ ${#metrics[@]} -eq 0 ]] && metrics=(cpu ram gpu fan bat)

for metric in "${metrics[@]}"; do
    case "$metric" in
        cpu)
            usage=$(top -bn2 -d1 | awk '
                /^%Cpu/ {cpu=$2}
                /^CPU:/ {gsub(/%/,"",$2); cpu=$2}
                END {if(cpu) printf "%.0f", cpu}
            ')
            temp=$(sensors 2>/dev/null | grep -E '^(Package id 0|Tctl|Core 0):' | head -1 | sed 's/^[^+]*+\([0-9.]*\).*/\1/')
            cur_freq=$(awk '{sum+=$1; count++} END {if(count>0) printf "%.1f", sum/count/1000000}' /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null)
            max_freq=$(awk '{print $1/1000000; exit}' /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
            freq_str=""
            [[ -n "$cur_freq" && -n "$max_freq" ]] && freq_str=" @ ${cur_freq}/${max_freq}GHz"
            if [[ ${#metrics[@]} -eq 1 ]]; then
                # Detailed output
                if [[ -n "$usage" ]]; then
                    [[ -n "$temp" ]] && printf "CPU %s%% (%s°C)%s\n" "$usage" "${temp%%.*}" "$freq_str" || printf "CPU %s%%%s\n" "$usage" "$freq_str"
                fi
                sensors 2>/dev/null | awk '/^Core [0-9]+:/ {gsub(/\+|°C/,""); printf "%s %s°C\n", $1$2, $3}'
                echo ""
                ps aux --sort=-%cpu | awk 'NR>1 && $3>3 {
                    cmd=$11; gsub(/^.*\//, "", cmd)
                    printf "%.0f%% %s (%s)\n", $3, cmd, $2
                }'
            else
                if [[ -n "$usage" ]]; then
                    [[ -n "$temp" ]] && printf "CPU %s%% (%s°C)%s\n" "$usage" "${temp%%.*}" "$freq_str" || printf "CPU %s%%%s\n" "$usage" "$freq_str"
                fi
            fi
            ;;
        ram)
            if [[ ${#metrics[@]} -eq 1 ]]; then
                free -h | awk '/^Mem:/ {
                    total=$2; used=$3; free=$4; available=$7
                    printf "RAM %.0f%% (%s / %s)\n", ($3/$2*100), used, total
                    printf "Used: %s | Free: %s | Available: %s\n", used, free, available
                }' RS='\n' FS='[[:space:]]+'
                echo ""
                ps aux --sort=-%mem | awk 'NR>1 && $4>4 {
                    cmd=$11; gsub(/^.*\//, "", cmd)
                    printf "%.0f%% %s (%s)\n", $4, cmd, $2
                }'
            else
                free | awk '/^Mem:/ {printf "RAM %.0f%%\n", $3/$2*100}'
            fi
            ;;
        gpu)
            # Detect hybrid setup
            has_igpu=$(lspci 2>/dev/null | grep -qi '00:02.0.*vga' && echo 1)
            discrete_addr=$(lspci -D 2>/dev/null | grep -iE 'vga|3d' | grep -v '0000:00:02' | awk '{print $1}' | head -1)
            pkg_temp=$(sensors 2>/dev/null | grep -E '^Package id 0:' | sed 's/^[^+]*+\([0-9.]*\).*/\1/')

            # iGPU - use frequency as activity indicator
            if [[ -n "$has_igpu" ]]; then
                igpu_card=$(for c in /sys/class/drm/card[0-9]; do [[ -f "$c/gt_cur_freq_mhz" ]] && echo "$c" && break; done)
                cur_freq=$(cat "$igpu_card/gt_cur_freq_mhz" 2>/dev/null)
                max_freq=$(cat "$igpu_card/gt_max_freq_mhz" 2>/dev/null)
                if [[ -n "$cur_freq" && -n "$max_freq" && "$max_freq" -gt 0 ]]; then
                    pct=$((cur_freq * 100 / max_freq))
                    if [[ ${#metrics[@]} -eq 1 ]]; then
                        printf "iGPU %s%% (%s°C) @ %s/%sMHz\n" "$pct" "${pkg_temp%%.*}" "$cur_freq" "$max_freq"
                    else
                        [[ -n "$pkg_temp" ]] && printf "iGPU %s%% (%s°C)\n" "$pct" "${pkg_temp%%.*}" || printf "iGPU %s%%\n" "$pct"
                    fi
                elif [[ -n "$discrete_addr" ]]; then
                    printf "iGPU\n"
                fi
            fi

            # dGPU with stats
            if [[ -n "$discrete_addr" ]]; then
                power_state=$(cat "/sys/bus/pci/devices/$discrete_addr/power/runtime_status" 2>/dev/null)
                if [[ "$power_state" == "suspended" ]]; then
                    printf "dGPU [suspended]\n"
                elif command -v nvidia-smi &>/dev/null; then
                    usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)
                    nv_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1)
                    if [[ ${#metrics[@]} -eq 1 ]]; then
                        mem=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
                        mem_used=$(echo "$mem" | cut -d',' -f1 | xargs)
                        mem_total=$(echo "$mem" | cut -d',' -f2 | xargs)
                        [[ -n "$usage" && -n "$nv_temp" ]] && printf "dGPU %s%% (%s°C) | %sMB/%sMB\n" "$usage" "${nv_temp%%.*}" "$mem_used" "$mem_total"
                        echo ""
                        nvidia-smi --query-compute-apps=pid,used_memory,process_name --format=csv,noheader 2>/dev/null | while read -r line; do
                            [[ -n "$line" ]] && echo "$line"
                        done
                    else
                        [[ -n "$usage" && -n "$nv_temp" ]] && printf "dGPU %s%% (%s°C)\n" "$usage" "${nv_temp%%.*}"
                    fi
                fi
            elif command -v nvidia-smi &>/dev/null; then
                # Single NVIDIA GPU (no hybrid)
                usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)
                nv_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1)
                [[ -n "$usage" && -n "$nv_temp" ]] && printf "GPU %s%% (%s°C)\n" "$usage" "${nv_temp%%.*}"
            fi
            ;;
        fan|fans)
            if [[ ${#metrics[@]} -eq 1 ]]; then
                # Detailed output
                command -v sensors &>/dev/null && sensors | awk '/^fan[0-9]+:/ && /RPM/ {
                    name = $1; gsub(/:/, "", name); toupper(name)
                    match($0, /[[:space:]]+([0-9]+) RPM/, cur)
                    match($0, /max = ([0-9]+) RPM/, mx)
                    current = cur[1]; max = mx[1]
                    if (max > 0) {
                        pct = int(current * 100 / max)
                        printf "%s %drpm (%d%% of %drpm)\n", toupper(name), current, pct, max
                    } else {
                        printf "%s %drpm\n", toupper(name), current
                    }
                }'
            else
                command -v sensors &>/dev/null && sensors | awk '/^fan[0-9]+:/ && /RPM/ {
                    match($0, /[[:space:]]+([0-9]+) RPM/, a); sum+=a[1]; count++
                } END {if(count>0) printf "FAN %.0frpm\n", sum/count}'
            fi
            ;;
        bat)
            for psu in /sys/class/power_supply/*; do
                [[ "$(cat "$psu/type" 2>/dev/null)" == "Battery" ]] || continue
                capacity=$(cat "$psu/capacity" 2>/dev/null)
                status=$(cat "$psu/status" 2>/dev/null)
                [[ -n "$capacity" ]] && printf "BAT %s%% (%s)\n" "$capacity" "$status"
            done
            ;;
    esac
done
