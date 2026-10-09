# Running GHOSTSHELL :: Relay Nine

This guide takes a clean Windows, macOS or Linux machine to a working relay.
Pick your platform, run the three commands, play.

No step here needs internet access except the one-time image build, which
downloads the Debian base image and the packages. Once built, the relay runs
fully offline — build it before you travel to the venue.

**Contents**

- [What you need](#what-you-need)
- [Windows](#windows)
- [macOS](#macos)
- [Linux](#linux)
- [Playing](#playing)
- [Hosting for a room](#hosting-for-a-room)
- [Stopping, resetting, removing](#stopping-resetting-removing)
- [Troubleshooting](#troubleshooting)
- [Running without Docker](#running-without-docker)

---

## What you need

| | Requirement |
|---|---|
| Container runtime | Docker Desktop, Docker Engine 23+, or Podman 4+ |
| SSH client | Already present on Windows 10/11, macOS and Linux |
| Disk | ~400 MB for the image |
| RAM | ~100 MB per running relay |
| Internet | Only for the first build |

Check what you have:

```bash
docker --version
ssh -V
```

---

## Windows

Docker Desktop on Windows runs containers inside WSL 2, which it sets up for
you. You do not need to install WSL separately.

### 1. Install Docker Desktop

Download from <https://www.docker.com/products/docker-desktop/>, run the
installer, and keep "Use WSL 2 instead of Hyper-V" ticked. Reboot when asked.

Launch Docker Desktop and wait for the whale icon in the system tray to stop
animating. **The whale must be steady before any `docker` command works.**

### 2. Get the files

If you have Git:

```powershell
git clone <repository-url>
cd ghostshell
```

Otherwise download the ZIP, extract it, and `cd` into the folder:

```powershell
cd $HOME\Downloads\ghostshell
```

### 3. Build and start

In **PowerShell** (not the old Command Prompt):

```powershell
docker compose build
docker compose up -d
```

The build takes two to five minutes the first time.

### 4. Play

```powershell
ssh level0@127.0.0.1 -p 2222
```

Password: `ghostshell`

> Windows ships OpenSSH as an optional feature that is on by default in
> Windows 10 1809 and later. If `ssh` is not recognised, see
> [Troubleshooting](#ssh-is-not-recognised-windows).

### Notes for Windows

- Run every command from the folder containing `docker-compose.yml`.
- Line endings matter. The shell scripts in this repository must stay LF, not
  CRLF, or the container will fail to start with `exec format error` or
  `bad interpreter`. If you cloned with Git on Windows and hit that, see
  [Troubleshooting](#container-exits-immediately-with-bad-interpreter-or-exec-format-error).
- `make` is not installed on Windows by default. Use the `docker compose`
  commands in this guide rather than the `make` shortcuts.

---

## macOS

### 1. Install a runtime

Either Docker Desktop from
<https://www.docker.com/products/docker-desktop/> (pick the Apple Silicon or
Intel build to match your Mac), or with Homebrew:

```bash
brew install --cask docker
```

Then launch Docker from Applications and wait for the menu-bar whale to go
steady.

Colima and OrbStack also work if you prefer them:

```bash
brew install colima docker docker-compose && colima start
```

### 2. Build and start

```bash
cd ~/Documents/ctf/ghostshell
docker compose build
docker compose up -d
```

### 3. Play

```bash
ssh level0@127.0.0.1 -p 2222
```

Password: `ghostshell`

Apple Silicon builds the image natively for `arm64` — no emulation and no
extra flags needed. If you want an `amd64` image for a mixed-architecture
event, see [Troubleshooting](#i-need-one-image-for-both-intel-and-apple-silicon).

---

## Linux

### 1. Install Docker Engine

Debian or Ubuntu:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
```

Fedora or RHEL:

```bash
sudo dnf install -y docker docker-compose-plugin
sudo systemctl enable --now docker
```

Arch:

```bash
sudo pacman -S docker docker-compose
sudo systemctl enable --now docker
```

### 2. Run docker without sudo (optional)

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

Without this, prefix every `docker` command with `sudo`.

### 3. Build and start

```bash
cd ghostshell
docker compose build
docker compose up -d
```

### 4. Play

```bash
ssh level0@127.0.0.1 -p 2222
```

Password: `ghostshell`

With `make` installed, `make up` and `make play` do the same thing.

---

## Playing

Connect as segment 0:

```bash
ssh level0@127.0.0.1 -p 2222
```

| Password | Value |
|---|---|
| `level0` | `ghostshell` |
| `level1` … `level5` | found inside the previous segment |

Inside the relay:

| Command | What it does |
|---|---|
| `ghost-brief` | Reprint what the current segment wants from you |
| `ghost-next` | Print the exact `ssh` command for the next segment |
| `ghost-submit` | Check the trophy flag at the end |

Two ways to move to the next segment — either works:

```bash
# from inside the relay
ssh level1@localhost -p 2222

# or log out (Ctrl-D) and connect from your own terminal
ssh level1@127.0.0.1 -p 2222
```

Your home directory is readable but **not writable**, so no one can break
their own puzzle. Use `/tmp` for scratch work.

### Suppressing host-key warnings

Host keys are generated fresh on first boot, so rebuilding the relay changes
them and SSH will complain. To skip the prompt entirely:

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    level0@127.0.0.1 -p 2222
```

That is safe here — it is your own laptop on port 2222 — and it keeps the
warning out of `~/.ssh/known_hosts`. `make play` already does this.

---

## Hosting for a room

By default the relay binds to `127.0.0.1:2222`, so only the host laptop can
reach it. To let other machines on the event LAN play against one laptop:

**1.** Edit `docker-compose.yml`:

```yaml
    ports:
      - "0.0.0.0:2222:2222"
```

**2.** Restart:

```bash
docker compose up -d
```

**3.** Find the host's LAN address:

```bash
# macOS
ipconfig getifaddr en0
# Linux
hostname -I | awk '{print $1}'
# Windows (PowerShell)
(Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.InterfaceAlias -notmatch 'Loopback|WSL|vEthernet' }).IPAddress
```

**4.** Players connect to it:

```bash
ssh level0@192.168.1.42 -p 2222
```

Allow inbound TCP 2222 on the host firewall if prompted. On Windows, Docker
Desktop usually adds the rule itself; approve it when the dialog appears.

### Capacity

One container handles a room comfortably. `MaxStartups 40:30:80` allows forty
unauthenticated connections at once, `MaxSessions` is 10 per connection, and
the compose file caps the relay at 2 CPUs, 1 GB RAM and 512 processes.

For a large event, give each team its own relay instead of sharing one — they
share accounts otherwise, and one team's `ssh level3` prompt is indistinguishable
from another's:

```bash
# team A on 2222, team B on 2223
docker run -d --name relay-a -p 2222:2222 ghostshell:1.0
docker run -d --name relay-b -p 2223:2222 ghostshell:1.0
```

Those shortcut commands skip the compose hardening flags. For a scored event,
copy the `security_opt`, `cap_drop`, `pids_limit` and `tmpfs` settings from
`docker-compose.yml` onto each `docker run`, or copy the compose file per team
and change the published port.

### Offline venues

Build the image at home, then carry it:

```bash
# on a machine with internet
docker compose build
docker save ghostshell:1.0 | gzip > ghostshell-1.0.tar.gz

# on the venue laptop, no internet needed
gunzip -c ghostshell-1.0.tar.gz | docker load
docker run -d --name ghostshell -p 2222:2222 ghostshell:1.0
```

The image file is around 400 MB and fits on any USB stick. Note that
`ghostshell-1.0.tar.gz` contains the keys for every level in its filesystem,
so treat that file as facilitator material.

---

## Stopping, resetting, removing

```bash
docker compose stop            # pause the relay, keep it around
docker compose up -d           # resume
docker compose restart         # clean slate for the next group
docker compose down            # stop and remove the container
docker compose build --no-cache && docker compose up -d   # full rebuild
docker rmi ghostshell:1.0      # delete the image
```

Level content lives in the image and homes are read-only, so `restart` is
enough between groups. Nothing a player does persists.

---

## Troubleshooting

### `docker: command not found` / `Cannot connect to the Docker daemon`

The runtime is not running. On Windows and macOS, launch Docker Desktop and
wait for the whale icon to stop animating. On Linux:

```bash
sudo systemctl start docker
```

### `permission denied while trying to connect to the Docker daemon` (Linux)

Your user is not in the `docker` group. Either prefix commands with `sudo`,
or:

```bash
sudo usermod -aG docker "$USER" && newgrp docker
```

### `ssh` is not recognised (Windows)

Install the built-in OpenSSH client from an **Administrator** PowerShell:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

Or use PuTTY with host `127.0.0.1`, port `2222`, username `level0`.

### `port is already allocated` / `bind: address already in use`

Something else holds 2222. Publish a different host port — edit
`docker-compose.yml`:

```yaml
    ports:
      - "127.0.0.1:2322:2222"
```

Then connect with `-p 2322`. Only the left-hand number changes; the relay
always listens on 2222 inside the container.

### `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`

Expected after a rebuild — the relay generated new host keys. Clear the old
entry:

```bash
ssh-keygen -R "[127.0.0.1]:2222"
```

On Windows, the file is `$HOME\.ssh\known_hosts`.

### `Permission denied, please try again`

- The password is case-sensitive and has no spaces. Type it rather than
  pasting if your terminal mangles clipboard content.
- Nothing echoes while you type a password. That is normal.
- Check you are using the right username for the key you found: the key
  inside segment 2 is `level3`'s password, not `level2`'s.

### Container exits immediately, `bad interpreter` or `exec format error`

The shell scripts were checked out with Windows line endings. Fix and rebuild:

```bash
git config core.autocrlf false
git rm --cached -r . && git reset --hard
docker compose build --no-cache
```

Without Git, convert in place:

```bash
sed -i 's/\r$//' setup_levels.sh entrypoint.sh tests/smoke_test.sh
```

A `.gitattributes` file forcing LF prevents this; add one if you fork the
repository.

### Build fails on `RUN --mount=type=bind`

Your Docker predates BuildKit defaults. Either upgrade to Docker 23+, or
build with BuildKit explicitly:

```bash
DOCKER_BUILDKIT=1 docker compose build
```

### Segment 4 says `DENIED` no matter what I send

The service compares the token exactly. Send it with `printf`, which does not
add anything of its own, and make sure the variable actually resolved:

```bash
echo "$GHOST_RELAY_TOKEN"
printf '%s\n' "$GHOST_RELAY_TOKEN" | nc 127.0.0.1 31337
```

If the variable is empty, you are in a shell that did not read the login
profile. Log out and SSH back in rather than using `bash -c`.

### A level looks broken rather than hard

Verify the relay itself before debugging a player's shell:

```bash
bash tests/smoke_test.sh
```

That solves every segment with the intended commands and checks the
permission model. If it passes, the relay is fine. Note that it prints the
keys, so run it somewhere players cannot see the screen.

### Podman instead of Docker

```bash
podman build -t ghostshell:1.0 .
podman run -d --name ghostshell -p 2222:2222 \
  --security-opt no-new-privileges --pids-limit 512 ghostshell:1.0
```

`podman-compose` also reads the compose file. Rootless Podman cannot publish
ports below 1024, which does not affect 2222.

### I need one image for both Intel and Apple Silicon

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t ghostshell:1.0 .
```

Or force a single architecture everyone can run:

```bash
docker build --platform linux/amd64 -t ghostshell:1.0 .
```

An `amd64` image runs on Apple Silicon under emulation — slower to build,
fine to play.

---

## Running without Docker

The game assumes one container per group because it creates six system
accounts, rewrites home-directory permissions, and strips every setuid bit on
the filesystem. **Do not run `setup_levels.sh` on a machine you care about.**

If you cannot use containers, run it in a throwaway VM:

1. Install Debian 12 or Ubuntu 24.04 in VirtualBox, UTM, Hyper-V or QEMU.
2. Install the tooling listed under "Included tooling" in the README.
3. Copy `setup_levels.sh` into the VM and run it as root.
4. Copy `sshd_config` to `/etc/ssh/sshd_config`, `motd` to `/etc/motd` and
   `banner` to `/etc/ghostshell-banner`, then restart `ssh`.
5. Start the auth subsystem: `python3 /opt/ghostshell/relayd.py &`
6. Delete `setup_levels.sh` from the VM — it contains every key.
7. Snapshot the VM so you can reset it between groups.

Players then SSH to the VM's address on port 2222. The container route is
less work and isolates players properly; prefer it when you have the choice.
