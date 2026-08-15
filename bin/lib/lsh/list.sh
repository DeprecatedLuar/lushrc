#!/usr/bin/env bash
# lsh ls/list — list configured SSH connections, optionally checking reachability

# Prints "+ name" (added/reachable), a dim "- name" (unreachable), or a dim
# strikethrough "x name" (removed) — mark is one of + - x. Shared by
# list/add/remove so they all agree on what each marker means. Styling is
# TTY-only; the ASCII mark itself always stays so piped/logged output
# remains distinguishable and greppable.
lsh_status_line() {
    local mark="$1" name="$2" style="" reset=""

    if [[ "$mark" == + ]]; then
        printf '+ %s\n' "$name"
        return
    fi

    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        reset=$'\033[0m'
        [[ "$mark" == x ]] && style=$'\033[2m\033[9m' || style=$'\033[2m'
    fi
    printf '%s%s %s%s\n' "$style" "$mark" "$name" "$reset"
}

lsh_list_entries() {
    local f
    for f in ~/.ssh/config ~/.ssh/config.d/*; do
        [[ -f "$f" ]] || continue
        awk '
            function flush() {
                if (name != "") {
                    if (hostname == "") hostname = name
                    endpoint = (user ? user "@" : "") hostname (port ? ":" port : "")
                    printf "%s\t%s\t%s\t%s\n", name, endpoint, hostname, (port ? port : "22")
                }
            }
            /^[Hh]ost[[:space:]]/ {
                flush()
                name = ($2 == "*") ? "" : $2
                hostname = ""; user = ""; port = ""
                next
            }
            name && tolower($1) == "hostname" { hostname = $2 }
            name && tolower($1) == "user" { user = $2 }
            name && tolower($1) == "port" { port = $2 }
            END { flush() }
        ' "$f"
    done | sort -u
}

lsh_list() {
    local check=false
    if (( $# > 1 )); then
        echo "Usage: lsh list [--status]" >&2
        return 1
    fi
    case "${1:-}" in
        "") [[ -t 1 ]] && check=true ;;
        --status) check=true ;;
        *)
            echo "Usage: lsh list [--status]" >&2
            return 1
            ;;
    esac

    local -a entries=()
    mapfile -t entries < <(lsh_list_entries)

    local entry name endpoint host port
    for entry in "${entries[@]}"; do
        IFS=$'\t' read -r name endpoint host port <<< "$entry"
        printf "%-16s %s\n" "$name" "$endpoint" 2>/dev/null || return 0
    done

    # Status is a terminal presentation feature. Keep pipes and redirected
    # output immediate, stable, and free of cursor-control sequences.
    [[ -t 1 ]] || return
    $check || return
    ((${#entries[@]})) || return

    command -v timeout >/dev/null 2>&1 || {
        echo "lsh status: 'timeout' is required" >&2
        return 1
    }

    local results entry name endpoint host port i
    results=$(mktemp -d) || return 1

    # Probe every SSH port concurrently. This checks TCP reachability only; it
    # deliberately does not authenticate or start an SSH session.
    for i in "${!entries[@]}"; do
        entry=${entries[$i]}
        IFS=$'\t' read -r name endpoint host port <<< "$entry"
        (
            if timeout 1 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; then
                printf reachable > "$results/$i"
            else
                printf unreachable > "$results/$i"
            fi
        ) &
    done
    wait || {
        rm -rf -- "$results"
        return 130
    }

    local wanted status dim=$'\033[2m' reset=$'\033[0m'

    # Replace the eager listing in place once every result is known.
    printf '\033[%dA\r' "${#entries[@]}"
    for wanted in reachable unreachable; do
        for i in "${!entries[@]}"; do
            status=$(<"$results/$i")
            [[ $status == "$wanted" ]] || continue
            entry=${entries[$i]}
            IFS=$'\t' read -r name endpoint host port <<< "$entry"
            if [[ $status == unreachable ]]; then
                printf '\033[2K%s- %-16s %s%s\n' "$dim" "$name" "$endpoint" "$reset"
            else
                printf '\033[2K+ %-16s %s\n' "$name" "$endpoint"
            fi
        done
    done

    rm -rf -- "$results"
}
