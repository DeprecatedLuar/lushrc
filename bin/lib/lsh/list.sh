#!/usr/bin/env bash
# lsh ls/list — list all configured SSH connections (name → user@host:port)

lsh_list() {
    local f
    for f in ~/.ssh/config ~/.ssh/config.d/*; do
        [[ -f "$f" ]] || continue
        awk '
            function flush() {
                if (name != "") printf "%-16s %s%s%s\n", name, user ? user "@" : "", hostname, port ? ":" port : ""
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
