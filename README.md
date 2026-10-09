# GHOSTSHELL :: Relay Nine

A self-contained, SSH-based terminal CTF. Six segments, one container, no
internet access required at any point during play.

Relay Nine is a signal station that went dark mid-shift. Each of its six
segments was sealed behind its own operator account, and the handover keys
were never collected. Players work forward one segment at a time: the key
material inside segment N is the SSH password for segment N+1. Segment 5
holds the trophy flag.

```
ssh level0@127.0.0.1 -p 2222        password: ghostshell
```

Everything a player needs is pre-installed in the image. The container runs
on an internal bridge and never calls out, so it works on an event LAN with
no uplink, on a plane, or in a room where the Wi-Fi has given up.

**New here? Read [RUNNING.md](RUNNING.md)** — it covers Windows, macOS and
Linux from a clean machine, plus hosting for a room.

---

## Contents

| File | What it is |
|---|---|
| `Dockerfile` | The relay image: tooling, sshd, hardening |
| `docker-compose.yml` | How the relay runs (ports, limits, capabilities) |
| `setup_levels.sh` | Provisions accounts, level content and permissions |
| `entrypoint.sh` | Host keys, auth subsystem, sshd supervision |
| `sshd_config` | SSH policy: passwords on, pivoting off |
| `motd` / `banner` | The intro players see on connect |
| `tests/smoke_test.sh` | Solves every segment and checks isolation |
| `deploy/*.ps1` | One-line start and stop for a Windows event host |
| `RUNNING.md` | Cross-platform run instructions |
| `SOLUTION.md` | **Spoilers.** Keys, intended commands, pitfalls |
| `Makefile` | Shortcuts for the commands above |

---

## Quick start

```bash
docker compose build
docker compose up -d
ssh level0@127.0.0.1 -p 2222          # password: ghostshell
```

Or with `make` on macOS and Linux:

```bash
make up        # build and start
make play      # ssh in as level0
make test      # solve every segment, verify isolation
make down      # stop and remove
```

Hosting an event from a **Windows** laptop? `make` is not available there, so
use the venue scripts instead — they build, publish to the LAN, add the
firewall rule and print the `ssh` line for the room:

```powershell
.\deploy\Start-Relay.ps1
.\deploy\Stop-Relay.ps1 -Clean
```

See [deploy/README.md](deploy/README.md) for the parameters and the one-time
execution-policy step.

---

## The segments

Each segment prints its own brief on login. Players can reprint it with
`ghost-brief`, get the next SSH command with `ghost-next`, and check the
trophy flag with `ghost-submit`.

| Segment | Theme | Skills exercised |
|---|---|---|
| 0 | **Cold boot** | Hidden directories, filenames that fight back (`ls -a`, `cat --`) |
| 1 | **Spool** | Finding one file among thousands by owner, group, size and mode (`find`) |
| 2 | **Chatter** | Searching 40,000 log lines, extracting a field, decoding it (`grep`, `awk`, `base64`) |
| 3 | **Blob** | Identifying files by header rather than name, unwrapping nested archives (`file`, `gunzip`, `tar`, `bunzip2`) |
| 4 | **Auth subsystem** | Reading the session environment, finding a listener, talking to it (`env`, `ss`, `nc`) |
| 5 | **Vault** | Reversing a transport encoding and decompressing the result (`xxd -r -p`, `gunzip`) |

The difficulty curve is deliberate: segment 0 teaches players that the
answer is often sitting in plain sight under a dot, and each later segment
adds one new idea rather than one new trick.

### Anti-guessing measures

Levels are built so that a half-formed idea does not accidentally succeed:

- Segment 1 contains 33-byte decoys owned by `root`, **and** files
  group-owned by `level1` of the wrong size. Neither predicate alone finds
  the answer — players have to combine them.
- Segment 2 contains three `KEYMAT-TEST` drill records whose payloads decode
  to a dead end, so `grep KEYMAT | base64 -d` is not enough.
- Segment 3's blob is compressed with `gzip -n`, which strips the original
  filename from the gzip header. `file` cannot leak the answer.
- Segment 4's service greeting deliberately avoids the phrase players grep
  for, so the intended one-liner parses cleanly.

---

## Included tooling

Installed in the image so no player ever needs a download:

```
shell / login     bash coreutils util-linux openssh-server
search / text     findutils grep sed gawk diffutils less
inspection        file binutils (strings) xxd bsdextrautils (hexdump)
archives          tar gzip bzip2 xz-utils zip unzip
network / script  python3 curl netcat-openbsd iproute2 net-tools procps
reference         man-db manpages, nano, vim-tiny, tree, jq, bc
```

Manual pages are deliberately **not** stripped from the image. "Read the man
page for the tool your brief names" is the intended hint path, and it only
works if `man find` actually resolves.

---

## Security model

Players get a real shell, so the game assumes they will poke at it.

**Between players**

- `/home/levelN` is `root:levelN` mode `0750`. A player can enter and read
  their own home and cannot even list anyone else's.
- Key material is mode `0440` owned by `root`. Players can read their own
  puzzle and cannot modify or delete it — nobody breaks their own level, and
  nobody can plant a fake flag for the next player.
- Homes are not writable. `/tmp` is the scratch space, mounted `nosuid,nodev`
  with the sticky bit set.

**Against escalation**

- Every setuid and setgid bit in the image is stripped at build time, so
  there is no `su`, no `passwd`, no local setuid path to root. `sudo` is not
  installed.
- `no-new-privileges` is set on the container, which independently blocks
  setuid and file-capability escalation on `exec`.
- Capabilities used for container escape and for sniffing other players'
  traffic are dropped: `SYS_ADMIN`, `SYS_PTRACE`, `SYS_MODULE`, `SYS_RAWIO`,
  `NET_ADMIN`, `NET_RAW`, `DAC_READ_SEARCH`, `MKNOD` and others.
- The package manager is root-only, so the image cannot be altered from
  inside a player session.
- `pids_limit` and per-account `nproc` limits mean one player cannot
  fork-bomb the room out of the game.

**Secrets**

- The segment 4 auth service reads the operator token and the segment 5 key
  from root-only files **at request time**. They are never in its argv or
  environment, so `/proc` gives nothing away even though `/proc` is visible.
- `setup_levels.sh` is bind-mounted for one `RUN` instruction and never
  committed to an image layer. The keys cannot be recovered with
  `docker save`, `docker history`, or by unpacking the image.

**Out of scope by design**

SSH password brute-forcing, attacking `sshd`, and reaching root are stated
as out of scope in the MOTD. Every key is findable with the tools provided.
`AllowTcpForwarding`, `PermitTunnel`, agent forwarding and X11 forwarding are
all off, so the relay cannot be used as a pivot into the event network.

---

## Verifying before an event

```bash
make up
make test
```

`tests/smoke_test.sh` logs in as each segment account, solves that segment
with the intended commands, and then asserts the permission model: that no
segment can read another's home, that homes are not writable, that puzzles
cannot be deleted, that no setuid binaries remain, that the provisioning
script is absent from the image, and that the auth service leaks nothing
through `/proc`.

Run it after any edit to `setup_levels.sh`. It contains the keys, so it is
facilitator material — see below.

---

## Rotating keys

The keys in this repository are public, so rotate them for anything scored.

1. Edit the `PASS_L1`–`PASS_L5`, `RELAY_TOKEN` and `TROPHY` variables at the
   top of `setup_levels.sh`.
2. Update the matching `EXPECT_*` values in `tests/smoke_test.sh` and the
   table in `SOLUTION.md`.
3. `make rebuild && make test`

`PASS_L0` is the published entry password and is meant to stay known.

Keep the segment 1 and segment 2 key lengths at 32 characters, or adjust the
level alongside them: segment 1's `find` predicate relies on the file being
exactly 33 bytes (32 characters plus a newline), and the provisioning script
fails the build if that ever drifts.

---

## Facilitator material

`SOLUTION.md` and `tests/smoke_test.sh` both contain the answers. If you plan
to hand players a clone of this repository rather than just a host and a
port, remove those two files from their copy first.

---

## Reset between sessions

Segment content is baked into the image and homes are read-only, so a restart
is a clean slate:

```bash
docker compose restart
```

A full rebuild (new host keys, new spool filenames, fresh everything):

```bash
make rebuild
```

---

## Requirements

Docker Engine 23 or newer, or Docker Desktop, or Podman 4+. The build needs
BuildKit, which is the default on all of those. Roughly 400 MB of disk for
the image and about 100 MB of RAM per container; the compose file caps it at
1 GB and 2 CPUs.

Players need an SSH client. Windows 10 and 11, macOS and Linux all ship one.

## License

MIT — see [LICENSE](LICENSE).
