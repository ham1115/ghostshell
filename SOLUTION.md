# GHOSTSHELL :: Relay Nine — Walkthrough and Reference Key

> **Spoilers.** This file contains every password and the trophy flag. It is
> facilitator material. Remove it from any copy of the repository you hand to
> players, along with `tests/smoke_test.sh`.

---

## Reference key

| Segment | Login | Password | How it is found |
|---|---|---|---|
| 0 | `level0` | `ghostshell` | Published — this is the entry point |
| 1 | `level1` | `aK3tVu9QmZr7LbXy2ChNdWf5Es8Gp1Jv` | `~/.relay/-manifest` in segment 0 |
| 2 | `level2` | `7HqRm2YtBv6XzKpL9NwScE4dJf1UaGo3` | The one real spool entry in segment 1 |
| 3 | `level3` | `Zx4Vb8NmQw1Er7TyUi5OpAs2DfGh9JkL` | Base64 payload in `relay.log` in segment 2 |
| 4 | `level4` | `3PnQs6WxZa9CvBm2TgYh5RdFj8KlUe1O` | Innermost layer of `relay.bin` in segment 3 |
| 5 | `level5` | `Mw7Jd2Hs9Kf4Lp6Qz1Xv3Bn8Tc5Ry0Ag` | Returned by the auth service in segment 4 |
| — | trophy | `GHOST{r3l4y_n1n3_g03s_d4rk_4t_d4wn}` | `vault.hex` in segment 5 |

Operator token used in segment 4:
`RLY9-7f3c1a84-OPERATOR-DELTA`

To rotate any of these, see "Rotating keys" in the README. The whole chain can
be re-verified in one command with `make test`.

---

## Segment 0 — Cold boot

**Teaches:** `ls` hides things by default, and a filename can be hostile.

```bash
ssh level0@127.0.0.1 -p 2222        # password: ghostshell

ls              # empty — this is the intended moment of doubt
ls -la          # .relay appears
cd .relay
ls -la          # a file called -manifest
cat ./-manifest
```

The whole thing in one line:

```bash
cat ~/.relay/-manifest
```

### The trap

`cat -manifest` fails, because `cat` reads the leading dash as an option:

```
cat: invalid option -- 'm'
```

Two correct ways out, both worth showing players:

```bash
cat ./-manifest      # make it a path, so it cannot look like a flag
cat -- -manifest     # -- ends option parsing
```

### Common pitfalls

- **`ls` shows nothing, so the home directory must be empty.** The most
  common first stumble. Dotfiles need `ls -a`. Worth saying out loud at the
  start of an event: on Linux, "empty" and "nothing visible" are different.
- **Fighting `cat: invalid option`.** Players often retry the same command
  harder, or try to quote the name (`cat "-manifest"`), which does not help
  because quoting removes shell meaning, not `cat`'s option parsing.
- **Trying to `mv` or rename the file first.** Home is read-only. That is
  deliberate: it pushes them toward `./` and `--`.

---

## Segment 1 — Spool

**Teaches:** `find` is a query language. Combining predicates is the point.

```bash
find /opt/relay/spool -type f -group level1 -size 33c
cat /opt/relay/spool/<dir>/<file>
```

In one go:

```bash
find /opt/relay/spool -type f -group level1 -size 33c -exec cat {} +
```

### Why both predicates are needed

The spool holds roughly 1,200 files. Deliberately:

- About 120 files are exactly 33 bytes, owned `root:root`. So
  `-size 33c` alone returns a long list.
- Six files are group-owned by `level1` but the wrong size. So
  `-group level1` alone returns seven files.
- Exactly one file satisfies both.

Players can confirm the narrowing as they go:

```bash
find /opt/relay/spool -type f -size 33c | wc -l        # ~120
find /opt/relay/spool -type f -group level1 | wc -l    # 7
find /opt/relay/spool -type f -group level1 -size 33c  # 1
```

Other routes that land on the same file: `-perm 0440` is on its own enough
(the real entry is the only mode-0440 file in the spool), and `ls -l` on the
seven group-owned candidates shows the answer by eye. Both are good answers —
the level is about narrowing with metadata, not about one exact incantation.

### Common pitfalls

- **`-size 33` instead of `-size 33c`.** Without a suffix, `find` counts
  512-byte blocks, so `-size 33` means roughly 16 KB and matches nothing.
  This is the single most common failure in this level; the brief says
  "33 bytes" precisely so the fix is findable in `man find`.
- **`grep -r` across the whole spool.** It works, eventually, and teaches
  nothing. If a player goes this way, ask them how they would do it if the
  spool were 40 GB.
- **Reading files one by one.** Some players open a dozen fragments looking
  for something that reads like a password. The brief tells them the entry is
  identifiable by metadata, not content.
- **Noise from `find /` without a path.** Searching from `/` produces
  permission errors that bury the result. `2>/dev/null` and a tighter start
  path both fix it.

---

## Segment 2 — Chatter

**Teaches:** locate the line, extract the field, decode the field.

```bash
grep KEYMAT relay.log
```

Four hits: three `KEYMAT-TEST` drills and one `KEYMAT rotation`. Only the
rotation record is real.

```bash
grep 'KEYMAT rotation' relay.log
# 2026-03-14T03:02:57Z relay[512] WARN KEYMAT rotation segment=3 payload=Wng0...

grep 'KEYMAT rotation' relay.log | awk -F'payload=' '{print $2}' | base64 -d
```

Equivalent extractions, all fine:

```bash
grep 'KEYMAT rotation' relay.log | cut -d= -f3 | base64 -d
grep -oP 'payload=\K\S+' relay.log | head -1 | base64 -d
grep 'KEYMAT rotation' relay.log | awk '{print $NF}' | sed 's/payload=//' | base64 -d
```

The drills decode to `drill-pattern-no-key-here`, which is intended to tell a
player they are on the right technique and the wrong line.

### Common pitfalls

- **Decoding the whole line.** `grep ... | base64 -d` without extracting the
  field gives `invalid input`, because the timestamp is not base64. Players
  need to isolate the payload first.
- **Decoding a drill record and concluding the level is broken.** The decoded
  text says it is not the key. Read it rather than skim it.
- **`grep KEYMAT | base64 -d` with all four lines piped in.** `base64`
  concatenates its input before decoding, so the result is garbage rather
  than one clean failure. Confusing unless you notice four lines went in.
- **Opening a 40,000-line file in an editor.** `nano relay.log` works but is
  a dead end; this is a `grep` problem.
- **Trailing whitespace.** Not an issue with the commands above, but if a
  player builds the payload by copy-paste, a stray space makes `base64 -d`
  fail. `tr -d '[:space:]'` before decoding is a good habit to teach.

---

## Segment 3 — Blob

**Teaches:** a file's type lives in its bytes, not its name.

Home is read-only, so work in `/tmp`:

```bash
cd /tmp
mkdir w && cd w
cp ~/relay.bin .

file relay.bin
# gzip compressed data, max compression
mv relay.bin a.gz && gunzip a.gz

file a
# POSIX tar archive
tar -xf a                      # yields core.img

file core.img
# bzip2 compressed data        <- the .img extension is a lie
mv core.img c.bz2 && bunzip2 c.bz2

file c
# ASCII text
cat c
```

The full chain, for a facilitator demo:

```bash
w=$(mktemp -d) && cp ~/relay.bin "$w/a.gz" && cd "$w" \
  && gunzip a.gz && tar -xf a && mv core.img c.bz2 && bunzip2 c.bz2 && cat c
```

`gzip -n` was used when building the blob, so the gzip header carries no
original filename and `file` cannot shortcut the puzzle.

### Common pitfalls

- **Working in the home directory.** `cp: cannot create regular file` or
  `gzip: Permission denied`. The brief says `/tmp` is the scratch space; this
  is a deliberate lesson about writable locations.
- **Trusting `core.img`.** It is bzip2 data, not a disk image. Players who
  reach for `mount` or `dd` here have stopped reading headers.
- **`gunzip` refusing to run.** `gunzip: unknown suffix -- ignored`. The tool
  wants a `.gz` name. Either rename, or use `gunzip -c relay.bin > next`, or
  `zcat`. Any of the three is a good answer.
- **Deleting the original.** They cannot, which is intentional — a player who
  mangles an intermediate file can start over with a fresh `cp`.
- **Stopping at `strings`.** `strings` on a compressed file shows noise.
  It is in the brief's tool list because it is worth trying and worth
  learning to abandon.

---

## Segment 4 — Auth subsystem

**Teaches:** your session carries state you were never shown, and services
listen on loopback.

```bash
env | grep -i ghost
# GHOST_RELAY_TOKEN=RLY9-7f3c1a84-OPERATOR-DELTA

ss -ltnp
# LISTEN 0 ... 127.0.0.1:31337
# LISTEN 0 ... 0.0.0.0:2222

printf '%s\n' "$GHOST_RELAY_TOKEN" | nc 127.0.0.1 31337
# RELAY NINE :: AUTH SUBSYSTEM
# present relay operator token:
# ACCEPTED :: operator recognised
# segment 5 key: Mw7Jd2Hs9Kf4Lp6Qz1Xv3Bn8Tc5Ry0Ag
```

Interactive also works, and is a good way to see what the service says:

```bash
nc 127.0.0.1 31337
# paste the token, press Enter
```

`netstat -ltnp` substitutes for `ss` for players who learned it that way.
Port discovery by scanning also works: `nc -zv 127.0.0.1 31330-31340`.

### Common pitfalls

- **Looking for the token in a file.** It is in the environment. `env`,
  `printenv` or `echo $GHOST_RELAY_TOKEN` find it; `grep -r` through the
  filesystem does not. `cat ~/.profile` also reveals it, which is a fair
  find rather than a bug.
- **`nc` seeming to hang.** With no input, `nc` waits. Piping with `printf`
  avoids it. If a player is stuck in an interactive session, Ctrl-C.
- **`echo` versus `printf`.** Both work here because the service strips
  whitespace, but `printf '%s\n'` is the habit worth teaching —
  `echo -e`/`echo -n` behave differently across shells.
- **Guessing the port.** The brief says to find it. Players who skip `ss`
  tend to try 80, 8080 and 443 and conclude nothing is running.
- **Trying to read the service's source or its secrets.** `/opt/ghostshell/relayd.py`
  is mode `0500 root:root` and `/etc/ghostshell/secrets/` is `0700 root`.
  Both are supposed to refuse. The service reads its secrets per request, so
  `/proc` does not expose them either.
- **Assuming the service is reachable from outside.** It binds to
  `127.0.0.1` only. From the host, `nc <host> 31337` fails by design.

---

## Segment 5 — Vault

**Teaches:** hex is a transport encoding, and compression has a signature.

```bash
head -c 60 vault.hex
# 1f8b080000000000020373f7f00f0ea92e32ce31a98ccf33cc338e4f3730

xxd -r -p vault.hex | file -b -
# gzip compressed data, max compression

xxd -r -p vault.hex | gunzip
# GHOST{r3l4y_n1n3_g03s_d4rk_4t_d4wn}
```

Then close the game out:

```bash
ghost-submit
# Trophy flag: GHOST{r3l4y_n1n3_g03s_d4rk_4t_d4wn}
#   ACCEPTED. Relay Nine is yours. Game over.
```

A player who recognises `1f8b08` as the gzip magic number has effectively
solved the level before decoding it — worth calling out if anyone spots it.

### Common pitfalls

- **`xxd -r` without `-p`.** Plain `-r` expects the full `xxd` layout with
  offsets and an ASCII column. The file is a bare hex stream, so it needs
  `-p` ("postscript"/plain) on the reverse too.
- **Writing the intermediate to the home directory.** Read-only. Pipe
  straight into `gunzip`, or write to `/tmp`.
- **`gunzip` complaining about a suffix.** Piping avoids it entirely; the
  pipeline above never names a file.
- **Submitting with the braces stripped**, or with a trailing space from a
  copy-paste. `ghost-submit` strips surrounding whitespace, but the braces
  are part of the flag.

---

## Facilitator notes

### Pacing

Segments 0 and 1 are where a mixed room spreads out the most — a player who
has never used `find` can sit on segment 1 for a while. If you are running to
a schedule, the hint ladder that works well is:

1. Re-read the brief out loud.
2. Name the tool, not the flag: "this is a `find` problem".
3. Name the flag, not the value: "`find` can filter on size".
4. Point at `man find` and the word "bytes".

### Hint budget

Each segment's brief already names the tools needed. If a player has not run
`man` on any of them, that is the hint to give rather than anything about the
puzzle.

### If a level appears broken

Run `bash tests/smoke_test.sh` on the host. It solves all six segments with
the commands above and verifies the permission model. If it passes, the relay
is healthy and the problem is in the player's shell — usually a missing `c`
on `-size 33c`, or a non-login shell in segment 4.

### Resetting between groups

```bash
docker compose restart
```

Homes are read-only and content is baked into the image, so nothing carries
over from the previous group.
