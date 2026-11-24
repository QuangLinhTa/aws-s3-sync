#!/usr/bin/env bash
set -euo pipefail

# Run the sync loop in the background; Nginx stays in the foreground as PID 1.
/usr/local/bin/sync.py loop &

exec nginx -g 'daemon off;'
