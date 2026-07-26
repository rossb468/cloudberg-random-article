#!/usr/bin/env bash
# Starts a local web server for app/ and opens it in the default browser.
# Stop the server with Ctrl+C.
set -euo pipefail

PORT="${PORT:-8743}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/app"
URL="http://localhost:${PORT}"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "${SERVER_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

(cd "${DIR}" && python3 -m http.server "${PORT}") &
SERVER_PID=$!

# Wait for the server to accept connections before opening the browser.
for _ in $(seq 1 50); do
  if curl --silent --fail --output /dev/null "${URL}"; then
    break
  fi
  sleep 0.1
done

echo "Serving ${DIR} at ${URL}"

if command -v open >/dev/null 2>&1; then
  open "${URL}"                      # macOS
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "${URL}"                  # Linux
elif command -v start >/dev/null 2>&1; then
  start "${URL}"                     # Windows (Git Bash/WSL)
else
  echo "Couldn't detect a way to auto-open a browser. Open ${URL} manually."
fi

wait "${SERVER_PID}"
