#!/usr/bin/env bash
# tunnel.sh — cloudflare tunnel integration for serve
# part of lushrc
# shared: cloudflare-tunnel.sh

source "$SYSDIR/shared/cloudflare-tunnel.sh"

SERVE_TUNNEL_PID_FILE="${TMPDIR:-/tmp}/serve-tunnel.pid"

# Start cloudflare tunnel and return public URL
# Usage: start_tunnel <port>
start_tunnel() {
  local port="$1"
  start_quick_tunnel "http://localhost:$port" "$SERVE_TUNNEL_PID_FILE"
}

# Stop tunnel
stop_tunnel() {
  stop_quick_tunnel "$SERVE_TUNNEL_PID_FILE"
}
