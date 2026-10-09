#!/usr/bin/env bash
# =====================================================================
#  GHOSTSHELL :: Relay Nine
#  setup_levels.sh — provisions users, level content and permissions.
#
#  Runs ONCE at image build time, as root, and is never shipped inside
#  the image (it is bind-mounted during build, see Dockerfile).
#
#  Permission model
#  ----------------
#    /home/levelN          root:levelN  0750   only levelN may enter
#    key material          root:levelN  0440   only levelN may read it,
#                                              nobody may modify it
#    /etc/ghostshell/secrets  root:root 0700   never readable by players
#
#  Each segment's key material contains the SSH password for the next
#  segment. Segment 5 holds the trophy flag.
# =====================================================================
set -euo pipefail

# ---------------------------------------------------------------------
# Keys. Change these before a public event (see README "Rotating keys").
# ---------------------------------------------------------------------
PASS_L0='ghostshell'                            # published entry password
PASS_L1='aK3tVu9QmZr7LbXy2ChNdWf5Es8Gp1Jv'
PASS_L2='7HqRm2YtBv6XzKpL9NwScE4dJf1UaGo3'
PASS_L3='Zx4Vb8NmQw1Er7TyUi5OpAs2DfGh9JkL'
PASS_L4='3PnQs6WxZa9CvBm2TgYh5RdFj8KlUe1O'
PASS_L5='Mw7Jd2Hs9Kf4Lp6Qz1Xv3Bn8Tc5Ry0Ag'
RELAY_TOKEN='RLY9-7f3c1a84-OPERATOR-DELTA'
TROPHY='GHOST{r3l4y_n1n3_g03s_d4rk_4t_d4wn}'

MAX_LEVEL=5

say() { printf '[setup] %s\n' "$*"; }

# ---------------------------------------------------------------------
# 1. Users
# ---------------------------------------------------------------------
say 'creating segment accounts'
for i in $(seq 0 "$MAX_LEVEL"); do
  if ! id -u "level$i" >/dev/null 2>&1; then
    useradd --create-home --home-dir "/home/level$i" \
            --shell /bin/bash --no-log-init "level$i"
  fi
done

chpasswd <<EOF
level0:$PASS_L0
level1:$PASS_L1
level2:$PASS_L2
level3:$PASS_L3
level4:$PASS_L4
level5:$PASS_L5
EOF

# Players must not be able to change their own password (it is the
# key another player will legitimately discover).
passwd -l root >/dev/null 2>&1 || true

# ---------------------------------------------------------------------
# 2. Shared scaffolding: briefs, helper commands, secrets
# ---------------------------------------------------------------------
say 'installing briefs and helper commands'
install -d -m 0755 /etc/ghostshell
install -d -m 0755 /etc/ghostshell/briefs
install -d -m 0700 /etc/ghostshell/secrets
install -d -m 0755 /opt/ghostshell

write_brief() { # write_brief <level> <<'TXT'
  local lvl="$1"
  cat > "/etc/ghostshell/briefs/level${lvl}.brief"
  chmod 0444 "/etc/ghostshell/briefs/level${lvl}.brief"
}

write_brief 0 <<'TXT'

  SEGMENT 0 :: COLD BOOT
  ----------------------------------------------------------------
  You are on Relay Nine. The station was abandoned mid-shift and
  every segment was locked behind its own operator account.

  The operator of this segment left a handover manifest in their
  home directory before walking out. It is not sitting in plain
  sight, and its filename was chosen badly.

  Recover the manifest. It carries the key to segment 1.

  Tools worth knowing here:  ls, cat
TXT

write_brief 1 <<'TXT'

  SEGMENT 1 :: SPOOL
  ----------------------------------------------------------------
  The relay's message spool is still on disk at /opt/relay/spool.
  It holds over a thousand dead fragments and exactly one entry
  that was addressed to this segment.

  That entry is the only file in the spool that is BOTH
  group-owned by your account AND exactly 33 bytes long.

  Nothing else in the spool matters. Do not read them all.

  Tools worth knowing here:  find, cat
TXT

write_brief 2 <<'TXT'

  SEGMENT 2 :: CHATTER
  ----------------------------------------------------------------
  relay.log in your home directory is roughly 40,000 lines of
  link chatter from the station's final hours.

  One line records a key rotation. The key itself was not written
  to the log in readable form, and there are rotation drills in
  there that are not the real event.

  Tools worth knowing here:  grep, awk, cut, base64
TXT

write_brief 3 <<'TXT'

  SEGMENT 3 :: BLOB
  ----------------------------------------------------------------
  relay.bin in your home directory has no extension and the name
  tells you nothing. It was wrapped for transport more than once.

  Identify what each layer actually is before you try to open it.
  Guessing by filename will waste your time.

  Your home directory is read-only to you. /tmp is yours to work in.

  Tools worth knowing here:  file, mv, gunzip, tar, bunzip2, xxd, strings
TXT

write_brief 4 <<'TXT'

  SEGMENT 4 :: AUTH SUBSYSTEM
  ----------------------------------------------------------------
  The station's auth subsystem is still running on this host, bound
  to the loopback interface only. It holds the key to segment 5.

  It will not talk to you until you present the relay operator
  token. That token was already loaded into your shell session when
  you logged in — you have never been shown it, but it is there.

  Find the listening port. Find the token. Speak to the service.

  Tools worth knowing here:  env, ss, netstat, nc, printf
TXT

write_brief 5 <<'TXT'

  SEGMENT 5 :: VAULT
  ----------------------------------------------------------------
  Last segment. The vault's contents were flattened into something
  that looks like text but is not text, so they would survive a
  7-bit link.

  Reverse the transport encoding, then decompress what falls out.
  Inside is the trophy flag. Submit it to close the game.

  Tools worth knowing here:  xxd, gunzip, file
TXT

# --- helper commands -------------------------------------------------
cat > /usr/local/bin/ghost-brief <<'SH'
#!/bin/sh
# Reprint the brief for the segment you are currently logged into.
f="/etc/ghostshell/briefs/$(id -un).brief"
if [ -r "$f" ]; then cat "$f"; else
  echo "No brief available for $(id -un)."
fi
SH
chmod 0555 /usr/local/bin/ghost-brief

cat > /usr/local/bin/ghost-next <<'SH'
#!/bin/sh
# Print the command used to move to the next segment.
me="$(id -un)"
n="$(printf '%s' "$me" | tr -dc '0-9')"
[ -n "$n" ] || { echo "Not inside a segment account."; exit 1; }
if [ "$n" -ge 5 ]; then
  echo "Segment 5 is the last one. Submit the trophy flag to finish."
  exit 0
fi
echo "ssh level$((n+1))@127.0.0.1 -p 2222"
echo
echo "You may also run this from inside the relay:"
echo "  ssh level$((n+1))@localhost -p 2222"
SH
chmod 0555 /usr/local/bin/ghost-next

cat > /usr/local/bin/ghost-submit <<'SH'
#!/bin/sh
# Check a trophy flag without revealing it.
printf 'Trophy flag: '
read -r guess
want="$(cat /etc/ghostshell/trophy.sha256 2>/dev/null)"
got="$(printf '%s' "$guess" | tr -d '[:space:]' | sha256sum | cut -d' ' -f1)"
if [ -n "$want" ] && [ "$got" = "$want" ]; then
  echo
  echo "  ACCEPTED. Relay Nine is yours. Game over."
  echo
else
  echo "  Rejected."
fi
SH
chmod 0555 /usr/local/bin/ghost-submit

printf '%s' "$TROPHY" | sha256sum | cut -d' ' -f1 > /etc/ghostshell/trophy.sha256
chmod 0444 /etc/ghostshell/trophy.sha256

# --- secrets used by the auth subsystem (never player-readable) ------
printf '%s\n' "$RELAY_TOKEN" > /etc/ghostshell/secrets/relay.token
printf '%s\n' "$PASS_L5"     > /etc/ghostshell/secrets/level5.pass
chmod 0400 /etc/ghostshell/secrets/*
chown root:root /etc/ghostshell/secrets/*

# ---------------------------------------------------------------------
# 3. Per-user shell environment
# ---------------------------------------------------------------------
say 'writing shell environment'
for i in $(seq 0 "$MAX_LEVEL"); do
  u="level$i"
  h="/home/$u"
  rm -f "$h"/.bashrc "$h"/.profile "$h"/.bash_logout "$h"/.bash_history

  {
    echo '# GHOSTSHELL segment shell'
    echo 'case $- in *i*) ;; *) return;; esac'
    echo 'export HISTFILE=/dev/null'
    echo 'export HISTSIZE=0'
    echo 'export PAGER=less'
    echo 'umask 077'
    echo "PS1='\\[\\e[1;32m\\]\\u\\[\\e[0m\\]@relay9:\\[\\e[1;34m\\]\\w\\[\\e[0m\\]\$ '"
    echo "alias ll='ls -lah'"
    echo 'ghost-brief'
  } > "$h/.bashrc"

  # The segment 4 token goes in .profile, not .bashrc. .bashrc returns
  # early for non-interactive shells, so an export placed there would be
  # missing from any login shell that is not a terminal — which would make
  # segment 4 behave differently depending on how the player connected.
  # .profile is read by every login shell either way.
  {
    if [ "$i" -eq 4 ]; then
      echo "export GHOST_RELAY_TOKEN='$RELAY_TOKEN'"
      echo
    fi
    cat <<'SH'
if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
SH
  } > "$h/.profile"
done

# ---------------------------------------------------------------------
# 4. SEGMENT 0 — hidden directory + hostile filename
# ---------------------------------------------------------------------
say 'building segment 0'
install -d /home/level0/.relay
cat > '/home/level0/.relay/-manifest' <<EOF
RELAY NINE :: HANDOVER MANIFEST
segment.........: 0
operator........: (signed out, 03:14)
status..........: cold

Shift ended early. Everything downstream is still sealed.
Spool access for the next segment is below. Do not write it down
anywhere else.

  segment 1 key: $PASS_L1

-- end of manifest --
EOF

# ---------------------------------------------------------------------
# 5. SEGMENT 1 — spool haystack, find by group + size
# ---------------------------------------------------------------------
say 'building segment 1 spool'
install -d -m 0755 /opt/relay/spool

python3 - <<'PY'
import os, random, string
random.seed(0xC0FFEE)
root = "/opt/relay/spool"
words = ["relay","trunk","uplink","burst","carrier","sync","frame","pulse",
         "echo","drift","beacon","hop","segment","packet","queue","spur"]
for d in range(40):
    sub = os.path.join(root, f"{random.choice(words)}-{random.randrange(16**6):06x}")
    os.makedirs(sub, exist_ok=True)
    for f in range(30):
        # Deliberately include some 33-byte decoys; they are root:root,
        # so size alone is not enough to find the real entry.
        n = 33 if f % 11 == 0 else random.choice(
            [12, 18, 24, 29, 31, 32, 34, 37, 48, 64, 97, 140, 203])
        body = "".join(random.choice(string.ascii_letters + string.digits)
                       for _ in range(max(n - 1, 0)))
        with open(os.path.join(sub, f"frag-{random.randrange(16**8):08x}.spl"), "w") as fh:
            fh.write(body + "\n")
PY

find /opt/relay/spool -type d -exec chmod 0755 {} +
find /opt/relay/spool -type f -exec chmod 0644 {} +
chown -R root:root /opt/relay/spool

# Group-owned decoys of the WRONG size: group alone is not enough either.
# shellcheck disable=SC2012
for f in $(find /opt/relay/spool -type f -size -30c | sort | head -n 6); do
  chown root:level1 "$f"
  chmod 0640 "$f"
done

# The one real entry: group level1 AND exactly 33 bytes.
real_dir="$(find /opt/relay/spool -mindepth 1 -maxdepth 1 -type d | sort | sed -n '17p')"
real="$real_dir/frag-$(printf '%08x' $((RANDOM * RANDOM % 4294967295))).spl"
printf '%s\n' "$PASS_L2" > "$real"          # 32 chars + newline = 33 bytes
chown root:level1 "$real"
chmod 0440 "$real"
[ "$(stat -c '%s' "$real")" = "33" ] || { echo "FATAL: segment 1 size drift"; exit 1; }

# ---------------------------------------------------------------------
# 6. SEGMENT 2 — 40k line log, one base64 rotation record
# ---------------------------------------------------------------------
say 'building segment 2 log'
PASS_L3="$PASS_L3" python3 - <<'PY'
import base64, os, random
random.seed(0xBADC0DE)
secret = os.environ["PASS_L3"]
levels = ["INFO"] * 24 + ["WARN"] * 3 + ["DEBUG"] * 8 + ["ERROR"]
msgs = [
    "heartbeat ok seq={n}",
    "carrier lock trunk={t} snr={s}db",
    "frame drift corrected delta={d}us",
    "uplink queue depth={n}",
    "peer relay-{t} hello ack",
    "buffer flush {n} frames",
    "sync pulse accepted jitter={d}us",
    "trunk={t} retrain complete",
    "session reaped pid={n}",
    "disk spool rotated files={n}",
]
decoys = [
    "KEYMAT-TEST drill payload={p}",
    "KEYMAT-TEST selftest payload={p}",
    "KEYMAT-TEST drill payload={p}",
]
lines = []
for i in range(40000):
    ts = f"2026-03-14T{i//1800%24:02d}:{i//30%60:02d}:{i%60:02d}Z"
    lines.append(f"{ts} relay[{random.randrange(400,999)}] "
                 f"{random.choice(levels)} "
                 + random.choice(msgs).format(
                     n=random.randrange(1, 99999),
                     t=random.randrange(1, 24),
                     s=random.randrange(12, 41),
                     d=random.randrange(1, 900)))

def enc(s):
    return base64.b64encode(s.encode()).decode()

for j, d in enumerate(decoys):
    pos = random.randrange(2000, 38000)
    lines[pos] = (f"2026-03-14T0{j+1}:0{j+2}:11Z relay[512] WARN "
                  + d.format(p=enc("drill-pattern-no-key-here")))

pos = random.randrange(9000, 31000)
lines[pos] = ("2026-03-14T03:02:57Z relay[512] WARN "
              "KEYMAT rotation segment=3 payload=" + enc(secret))

with open("/home/level2/relay.log", "w") as fh:
    fh.write("\n".join(lines) + "\n")
PY
grep -c 'KEYMAT rotation' /home/level2/relay.log | grep -qx 1 \
  || { echo "FATAL: segment 2 marker count wrong"; exit 1; }

# ---------------------------------------------------------------------
# 7. SEGMENT 3 — nested transport wrapping, identify by header
# ---------------------------------------------------------------------
say 'building segment 3 blob'
work="$(mktemp -d)"
(
  cd "$work"
  printf '%s\n' "$PASS_L4" > vault.key
  bzip2 -9 vault.key                 # -> vault.key.bz2
  mv vault.key.bz2 core.img          # extension now lies
  tar -cf relay.tar core.img
  gzip -n -9 relay.tar               # -n: strip original name + mtime
  mv relay.tar.gz /home/level3/relay.bin
)
rm -rf "$work"
file -b /home/level3/relay.bin | grep -qi gzip \
  || { echo "FATAL: segment 3 blob not gzip"; exit 1; }

# ---------------------------------------------------------------------
# 8. SEGMENT 4 — loopback auth service (token lives in the env)
# ---------------------------------------------------------------------
say 'installing segment 4 auth subsystem'
cat > /opt/ghostshell/relayd.py <<'PY'
#!/usr/bin/env python3
"""Relay Nine auth subsystem.

Listens on loopback only. Hands out the segment 5 key to any client
that presents the relay operator token.

Secrets are read from root-only files at request time and never appear
in argv or in this process's environment, so /proc gives nothing away.
"""
import socketserver

TOKEN_FILE = "/etc/ghostshell/secrets/relay.token"
PASS_FILE = "/etc/ghostshell/secrets/level5.pass"
HOST, PORT = "127.0.0.1", 31337


def _read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read().strip()


class Handler(socketserver.StreamRequestHandler):
    timeout = 20

    def handle(self):
        # Keep the phrase "segment 5 key" out of this banner: players
        # parse the reply with grep/awk and a decoy match in the greeting
        # turns a solved level into a confusing one.
        self.wfile.write(
            b"RELAY NINE :: AUTH SUBSYSTEM\n"
            b"present relay operator token:\n"
        )
        try:
            raw = self.rfile.readline(1024)
        except Exception:
            return
        if not raw:
            return
        offered = raw.decode("utf-8", "replace").strip()
        if offered and offered == _read(TOKEN_FILE):
            self.wfile.write(
                ("ACCEPTED :: operator recognised\n"
                 "segment 5 key: " + _read(PASS_FILE) + "\n").encode()
            )
        else:
            self.wfile.write(b"DENIED :: token rejected\n")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    Server((HOST, PORT), Handler).serve_forever()
PY
chown root:root /opt/ghostshell/relayd.py
chmod 0500 /opt/ghostshell/relayd.py

# ---------------------------------------------------------------------
# 9. SEGMENT 5 — hex transport encoding over gzip
# ---------------------------------------------------------------------
say 'building segment 5 vault'
printf '%s\n' "$TROPHY" | gzip -n -9 | xxd -p > /home/level5/vault.hex

# ---------------------------------------------------------------------
# 10. Lock everything down
# ---------------------------------------------------------------------
say 'applying permissions'
for i in $(seq 0 "$MAX_LEVEL"); do
  u="level$i"
  h="/home/$u"
  # Home readable+enterable by its own user only; NOT writable, so
  # players cannot delete or tamper with their own puzzle.
  chown -R root:"$u" "$h"
  find "$h" -type d -exec chmod 0750 {} +
  find "$h" -type f -exec chmod 0440 {} +
done

# Key material and puzzle inputs are read-only to the owning segment.
chmod 0440 '/home/level0/.relay/-manifest'
chmod 0440 /home/level2/relay.log
chmod 0440 /home/level3/relay.bin
chmod 0440 /home/level5/vault.hex

# Nobody needs set-user-ID or set-group-ID binaries in here. Removing
# them closes the usual local-escalation paths and also stops players
# from running `su` or changing a password that another player needs.
say 'stripping setuid/setgid bits'
find / -xdev -type f -perm -4000 -exec chmod u-s {} + 2>/dev/null || true
find / -xdev -type f -perm -2000 -exec chmod g-s {} + 2>/dev/null || true

# No sudo, no at, no cron for players.
rm -f /usr/bin/sudo /usr/bin/at /usr/bin/crontab 2>/dev/null || true

# Shadow stays root:shadow 0640 (distro default) — verify it.
chmod 0640 /etc/shadow
chown root:shadow /etc/shadow

# Limit fork bombs even if the container's pid limit is forgotten. The
# limit is applied per player account and NOT with a `*` wildcard: a
# wildcard would also cap root, and sshd forks a process per connection,
# so a room full of players could trip over it during a login rush.
{
  echo
  echo '# GHOSTSHELL: keep one player from taking down the relay'
  for i in $(seq 0 "$MAX_LEVEL"); do
    printf 'level%s\thard\tnproc\t120\n' "$i"
    printf 'level%s\thard\tnofile\t1024\n' "$i"
  done
} >> /etc/security/limits.conf

say 'verifying isolation'
fail=0
for i in $(seq 0 "$MAX_LEVEL"); do
  for j in $(seq 0 "$MAX_LEVEL"); do
    [ "$i" = "$j" ] && continue
    if runuser -u "level$i" -- test -r "/home/level$j" 2>/dev/null; then
      echo "FATAL: level$i can read /home/level$j"; fail=1
    fi
  done
done
[ "$fail" = 0 ] || exit 1

say 'provisioning complete'
