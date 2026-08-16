#!/usr/bin/env bash

cat <<'EOF'
Usage: vch [COMMAND | PORT | PROCESS] [OPTIONS]

System metrics:
  cpu                     CPU usage, temperatures, and processes
  ram [--all]             Memory usage and processes
  gpu | igpu | dgpu       GPU usage and processes
  fan | fans              Fan speeds
  bat                     Battery status
  disk | storage          Disk usage

Ports and processes:
  port, --port PORT       Show the process listening on PORT
  ports, --ports          List listening ports
    -a, --all             Include system services (uses sudo)
    -i, --ip              Include listening addresses
  :PORT                   Shorthand for an explicit port lookup
  PORT                    Infer a port lookup from a number
  PROCESS                 Find a process by name

Other commands:
  ip                      Show local and public IP addresses
  net | internet          Check network health and speed
  hw | hardware [PART]    Show hardware information
  tray                    List tray applications

Options:
  -h, --help              Show this help

With no arguments, vch prints a system metrics summary.
EOF
