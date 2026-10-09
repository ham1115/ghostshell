#!/usr/bin/env bash
# =====================================================================
#  GHOSTSHELL :: Relay Nine — container entrypoint
#
#  1. generate SSH host keys on first boot (never baked into the image)
#  2. start the segment 4 auth subsystem on loopback
#  3. supervise both processes; if either dies, exit so the container's
#     restart policy brings the relay back rather than leaving a level
#     quietly unsolvable
# =====================================================================
set -euo pipefail

log() { printf '[ghostshell] %s\n' "$*"; }

# ---------------------------------------------------------------------
# 1. Host keys
# ---------------------------------------------------------------------
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
  log 'generating SSH host keys'
  ssh-keygen -A >/dev/null 2>&1
fi
install -d -m 0755 /run/sshd

# ---------------------------------------------------------------------
# 2. Segment 4 auth subsystem (127.0.0.1:31337)
# ---------------------------------------------------------------------
log 'starting auth subsystem on 127.0.0.1:31337'
/usr/bin/python3 /opt/ghostshell/relayd.py &
RELAYD_PID=$!

sleep 1
if ! kill -0 "$RELAYD_PID" 2>/dev/null; then
  log 'FATAL: auth subsystem died on startup — segment 4 would be unsolvable'
  exit 1
fi

# ---------------------------------------------------------------------
# 3. sshd
# ---------------------------------------------------------------------
/usr/sbin/sshd -D -e &
SSHD_PID=$!

cleanup() {
  log 'shutting down'
  kill "$RELAYD_PID" "$SSHD_PID" 2>/dev/null || true
  wait "$RELAYD_PID" "$SSHD_PID" 2>/dev/null || true
  exit 0
}
trap cleanup TERM INT

log 'relay is up — ssh level0@<host> -p 2222'
wait -n "$RELAYD_PID" "$SSHD_PID"
log 'a relay process exited; stopping container'
kill "$RELAYD_PID" "$SSHD_PID" 2>/dev/null || true
exit 1
