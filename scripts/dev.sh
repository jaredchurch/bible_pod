#!/bin/bash
#######################################################################
#
#   FileName: dev.sh
#
#   Purpose: Starts a local static web server for developing the site in
#            public/. Wraps python3's http.server so the dev loop needs no
#            global npm install and no checked-in server code.
#
#######################################################################

set -e

# Resolve repo root as the parent of scripts/, so the site is found the same
# way no matter which directory the script is invoked from
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Overridable via environment so a second instance can run without editing
DOCROOT="${DOCROOT:-$REPO_ROOT/public}"
BIND="${BIND:-127.0.0.1}"
PORT="${PORT:-8000}"

usage() {
    cat <<EOF
Usage: scripts/dev.sh

Serves \$DOCROOT (default: public/) over HTTP.

Environment:
  PORT     port to listen on          (default: 8000)
  BIND     address to bind            (default: 127.0.0.1, loopback only)
  DOCROOT  directory to serve         (default: <repo>/public)
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 not found on PATH" >&2
    exit 1
fi

if [ ! -d "$DOCROOT" ]; then
    echo "ERROR: docroot '$DOCROOT' does not exist" >&2
    exit 1
fi

# Probe the port up front: http.server would otherwise abort with a traceback
# that reads like a bug in the site rather than a busy port
if ! python3 - "$BIND" "$PORT" <<'EOF'
import socket, sys

sock = socket.socket()
try:
    sock.bind((sys.argv[1], int(sys.argv[2])))
except OSError:
    sys.exit(1)
finally:
    sock.close()
EOF
then
    echo "ERROR: port $PORT is already in use on $BIND" >&2
    echo "       stop it, or run with PORT=8001 scripts/dev.sh" >&2
    exit 1
fi

echo "Serving $DOCROOT at http://$BIND:$PORT/ (Ctrl+C to stop)"

# exec so the server becomes PID of this script and receives SIGINT directly,
# giving a clean shutdown with no orphaned python process left behind
exec python3 -m http.server "$PORT" --bind "$BIND" --directory "$DOCROOT"