#!/usr/bin/env bash
# =====================================================================
#  GHOSTSHELL :: Relay Nine — smoke test  (FACILITATOR ONLY: contains keys)
#
#  Solves every segment with the intended commands, as the intended
#  user, and checks that the permission model actually isolates levels.
#  Run this after any edit to setup_levels.sh and before an event.
#
#    ./tests/smoke_test.sh                 # against container "ghostshell"
#    CONTAINER=myrelay ./tests/smoke_test.sh
# =====================================================================
set -uo pipefail

CONTAINER="${CONTAINER:-ghostshell}"

EXPECT_L1='aK3tVu9QmZr7LbXy2ChNdWf5Es8Gp1Jv'
EXPECT_L2='7HqRm2YtBv6XzKpL9NwScE4dJf1UaGo3'
EXPECT_L3='Zx4Vb8NmQw1Er7TyUi5OpAs2DfGh9JkL'
EXPECT_L4='3PnQs6WxZa9CvBm2TgYh5RdFj8KlUe1O'
EXPECT_L5='Mw7Jd2Hs9Kf4Lp6Qz1Xv3Bn8Tc5Ry0Ag'
EXPECT_TROPHY='GHOST{r3l4y_n1n3_g03s_d4rk_4t_d4wn}'

pass=0; fail=0
GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; DIM=$'\033[2m'; OFF=$'\033[0m'

ok()   { pass=$((pass+1)); printf '  %sPASS%s  %s\n' "$GREEN" "$OFF" "$1"; }
bad()  { fail=$((fail+1)); printf '  %sFAIL%s  %s\n' "$RED" "$OFF" "$1"; }

# Run a command as a segment user inside the relay, in that user's home
# directory and through a login shell, so each level's own environment
# applies exactly as it does for a player who just logged in.
as() {
  local u="$1"; shift
  docker exec -u "$u" -w "/home/$u" "$CONTAINER" bash -lc "$*" 2>/dev/null
}

check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"
  else bad "$1"; printf '        %sexpected:%s %s\n        %sgot:     %s %s\n' \
        "$DIM" "$OFF" "$2" "$DIM" "$OFF" "$3"; fi
}

refute() { # refute <label> <command that must FAIL as that user>
  local label="$1" u="$2"; shift 2
  if docker exec -u "$u" "$CONTAINER" bash -lc "$*" >/dev/null 2>&1
  then bad "$label (it succeeded and should not have)"
  else ok "$label"; fi
}

printf '\n== GHOSTSHELL smoke test (container: %s) ==\n\n' "$CONTAINER"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  printf '%sContainer "%s" is not running. Start it with: docker compose up -d%s\n' \
    "$RED" "$CONTAINER" "$OFF"; exit 1
fi

# ---------------------------------------------------------------------
echo 'services'
# ---------------------------------------------------------------------
check 'sshd listening on 2222' 'yes' \
  "$(as level0 'nc -z 127.0.0.1 2222 && echo yes')"
check 'auth subsystem listening on 31337' 'yes' \
  "$(as level0 'nc -z 127.0.0.1 31337 && echo yes')"

# ---------------------------------------------------------------------
echo
echo 'segment solutions (intended commands)'
# ---------------------------------------------------------------------

# Segment 0 — hidden dir, leading-dash filename
check 'segment 0 -> level1 key' "$EXPECT_L1" \
  "$(as level0 'cat -- ./.relay/-manifest | awk "/segment 1 key/ {print \$4}"')"

# Segment 1 — find by group + exact size
check 'segment 1 -> level2 key' "$EXPECT_L2" \
  "$(as level1 'find /opt/relay/spool -type f -group level1 -size 33c -exec cat {} +')"

# Segment 2 — grep the real rotation record, decode base64
check 'segment 2 -> level3 key' "$EXPECT_L3" \
  "$(as level2 'grep "KEYMAT rotation" relay.log | awk -F"payload=" "{print \$2}" | base64 -d')"

# Segment 3 — identify each wrapper by header, unwrap in /tmp
check 'segment 3 -> level4 key' "$EXPECT_L4" \
  "$(as level3 'w=$(mktemp -d) && cp relay.bin "$w/a.gz" && cd "$w" \
       && gunzip a.gz && tar -xf a && mv core.img c.bz2 && bunzip2 c.bz2 \
       && cat c; rm -rf "$w"')"

# Segment 4 — token from the environment, loopback service.
# The token must be present in EVERY login shell, not just interactive
# ones, or the level behaves differently depending on how you connected.
check 'segment 4 token present in login environment' 'set' \
  "$(as level4 '[ -n "$GHOST_RELAY_TOKEN" ] && echo set')"
check 'segment 4 -> level5 key' "$EXPECT_L5" \
  "$(as level4 'printf "%s\n" "$GHOST_RELAY_TOKEN" | nc 127.0.0.1 31337 \
       | awk "/segment 5 key/ {print \$4}"')"
check 'auth service refuses a wrong token' 'DENIED' \
  "$(as level4 'printf "not-the-token\n" | nc 127.0.0.1 31337 | awk "/DENIED/{print \"DENIED\"}"')"
# The greeting must not contain the phrase players grep for, or a decoy
# match in the banner silently breaks the intended one-liner.
check 'auth greeting has no decoy key match' '0' \
  "$(as level4 'printf "x\n" | nc 127.0.0.1 31337 | grep -c "segment 5 key"')"

# Segment 5 — reverse hex transport, decompress
check 'segment 5 -> trophy flag' "$EXPECT_TROPHY" \
  "$(as level5 'xxd -r -p vault.hex | gunzip')"

# Trophy checker accepts the real flag
check 'ghost-submit accepts the trophy' 'ACCEPTED' \
  "$(as level5 "printf '%s\n' '$EXPECT_TROPHY' | ghost-submit | awk '/ACCEPTED/{print \"ACCEPTED\"}'")"
check 'ghost-submit rejects a wrong flag' 'Rejected' \
  "$(as level5 "printf 'GHOST{nope}\n' | ghost-submit | awk '/Rejected/{print \"Rejected\"}'")"

# ---------------------------------------------------------------------
echo
echo 'isolation and hardening'
# ---------------------------------------------------------------------
for n in 1 2 3 4 5; do
  refute "level0 cannot read /home/level$n" level0 "ls /home/level$n"
done
refute 'level1 cannot read segment 2 log'      level1 'cat /home/level2/relay.log'
refute 'level4 cannot read the relay token'    level4 'cat /etc/ghostshell/secrets/relay.token'
refute 'level4 cannot read the auth service'   level4 'cat /opt/ghostshell/relayd.py'
refute 'level5 cannot read /etc/shadow'        level5 'cat /etc/shadow'
refute 'players cannot write to their home'    level2 'touch ~/scratch'
refute 'players cannot delete their puzzle'    level3 'rm -f ~/relay.bin'
refute 'no su available to players'            level1 'su -c true root'
refute 'no sudo installed'                     level1 'command -v sudo'

check 'no setuid binaries remain' '0' \
  "$(as level0 'find / -xdev -type f -perm -4000 2>/dev/null | wc -l')"
check '/tmp is writable (scratch space)' 'yes' \
  "$(as level3 'touch /tmp/.probe.$$ && echo yes && rm -f /tmp/.probe.$$')"
check 'provisioning script not shipped in image' '0' \
  "$(as level0 'find / -xdev -name "setup_levels.sh" 2>/dev/null | wc -l')"

# Keys must not be greppable from anywhere a player can read. The pattern
# is passed through a file so it never appears in a process command line
# that the grep would then match on itself.
check 'level5 key not readable by lower segments' '0' \
  "$(docker exec -i "$CONTAINER" bash -c \
      'cat > /tmp/.pat && runuser -u level1 -- grep -rlFf /tmp/.pat /home /opt /etc 2>/dev/null | wc -l; rm -f /tmp/.pat' \
      <<<"$EXPECT_L5" 2>/dev/null)"

# The auth service must not leak its secrets through /proc: it reads them
# from root-only files per request rather than holding them in argv or env.
check 'auth service does not expose secrets via /proc' '0' \
  "$(docker exec -i "$CONTAINER" bash -c \
      'p=$(pgrep -f "[r]elayd.py" | head -1); [ -n "$p" ] || { echo ERR; exit; }
       { tr "\0" " " < /proc/$p/cmdline; tr "\0" " " < /proc/$p/environ 2>/dev/null; } \
         | grep -cF "$(cat /etc/ghostshell/secrets/relay.token)"' 2>/dev/null)"

# ---------------------------------------------------------------------
printf '\n== %d passed, %d failed ==\n\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
printf 'Relay is event-ready.\n\n'
