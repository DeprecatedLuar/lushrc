#!/usr/bin/env bash
# tunnel.sh — cloudflare tunnel integration for serve
# part of lushrc

# Ensure cloudflared is installed
ensure_cloudflared() {
  if command -v cloudflared &>/dev/null; then
    return 0
  fi

  echo "  · cloudflared not found, installing..." >&2

  # Install via the-satellite
  curl -sSL "https://raw.githubusercontent.com/DeprecatedLuar/the-satellite/main/satellite.sh" | \
    bash -s -- install cloudflare/cloudflared || {
    echo "error: failed to install cloudflared" >&2
    return 1
  }

  # Verify installation
  if ! command -v cloudflared &>/dev/null; then
    echo "error: cloudflared installed but not found in PATH" >&2
    return 1
  fi
}

# Start cloudflare tunnel and return public URL
# Usage: start_tunnel <port>
start_tunnel() {
  local port="$1"
  local url_file tunnel_pid

  ensure_cloudflared || return 1

  # Temp file to capture the URL
  url_file=$(mktemp serve-tunnel-url.XXXXXX)

  # Start tunnel in background, capture output
  cloudflared tunnel --url "http://localhost:$port" > "$url_file" 2>&1 &
  tunnel_pid=$!

  # Store PID for cleanup
  echo "$tunnel_pid" > "${TMPDIR:-/tmp}/serve-tunnel.pid"

  # Wait for URL to appear (max 20 seconds)
  local waited=0
  local public_url=""

  while [[ $waited -lt 40 ]]; do
    # Check if process died
    if ! kill -0 "$tunnel_pid" 2>/dev/null; then
      echo "error: cloudflared process died" >&2
      cat "$url_file" >&2
      rm -f "$url_file"
      return 1
    fi

    # Look for URL in output (various possible formats)
    if grep -qE "https://[a-z0-9-]+\.trycloudflare\.com" "$url_file"; then
      public_url=$(grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" "$url_file" | head -1)
      break
    fi

    sleep 0.5
    waited=$((waited + 1))
  done

  if [[ -z "$public_url" ]]; then
    echo "error: failed to get tunnel URL after ${waited} attempts" >&2
    echo "cloudflared output:" >&2
    cat "$url_file" >&2
    rm -f "$url_file"
    kill "$tunnel_pid" 2>/dev/null || true
    return 1
  fi

  rm -f "$url_file"
  echo "$public_url"
}

# Stop tunnel
stop_tunnel() {
  local pid_file="${TMPDIR:-/tmp}/serve-tunnel.pid"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(cat "$pid_file")
    kill "$pid" 2>/dev/null || true
    rm -f "$pid_file"
  fi
}
