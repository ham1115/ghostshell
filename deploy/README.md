# Venue scripts (Windows host)

Two PowerShell helpers for running the relay at an event from a Windows
laptop, so you are not editing YAML and hunting for your IP address in front
of a room.

```powershell
.\deploy\Start-Relay.ps1          # build, start, publish to the LAN, print the ssh line
.\deploy\Stop-Relay.ps1           # stop it
.\deploy\Stop-Relay.ps1 -Clean    # stop it and tidy up after the event
```

Run them from the repository root, not from inside `deploy\`.

Nothing here is required — everything they do can be done by hand with the
`docker compose` commands in [RUNNING.md](../RUNNING.md). They exist to make
the venue sequence one line.

---

## First time: execution policy

Windows blocks unsigned scripts by default. Allow them for the current
PowerShell window only, which resets when you close it:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Or run a single script without changing any policy:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\Start-Relay.ps1
```

If you downloaded the repository as a ZIP rather than cloning it, Windows
also marks the files as coming from the internet:

```powershell
Get-ChildItem .\deploy\*.ps1 | Unblock-File
```

Cloning with `git` does not set that mark, so this is only needed for ZIPs.

---

## Start-Relay.ps1

What it does, in order: checks Docker is installed and the engine is actually
running, writes `docker-compose.override.yml` with your port binding, builds
the image, starts the relay, waits for SSH to answer, adds a Windows Firewall
rule, and prints the `ssh` command to read out to the room.

Every step is idempotent — run it again any time.

| Parameter | Default | What it does |
|---|---|---|
| `-Port` | `2222` | Host port players connect to |
| `-LocalOnly` | off | Bind `127.0.0.1` — this laptop only, no firewall rule |
| `-Name` | `ghostshell` | Compose project and container name |
| `-FirewallProfile` | `Private` | `Private`, `Domain`, `Public` or `Any` |
| `-NoBuild` | off | Start the existing image without rebuilding |
| `-SkipFirewall` | off | Print the firewall command instead of running it |

### Examples

One relay for the whole room:

```powershell
.\deploy\Start-Relay.ps1
```

Three isolated relays for three teams, on three ports:

```powershell
.\deploy\Start-Relay.ps1 -Name team-a -Port 2222
.\deploy\Start-Relay.ps1 -Name team-b -Port 2223 -NoBuild
.\deploy\Start-Relay.ps1 -Name team-c -Port 2224 -NoBuild
```

`-NoBuild` on the later ones reuses the image you just built. Separate relays
mean each team gets its own six accounts, which is what you want for anything
scored — see "Hosting for a room" in [RUNNING.md](../RUNNING.md).

Solo, on your own laptop:

```powershell
.\deploy\Start-Relay.ps1 -LocalOnly
```

### Administrator

The firewall rule needs an elevated PowerShell. Without one, everything else
still runs and the script prints the exact `New-NetFirewallRule` command to
paste into an admin window. If players cannot connect, that rule is the first
thing to check.

### Sleep

The script **reads** your AC sleep timeout and warns you if the laptop will
suspend, but does not change it — a system power setting is not something a
script should quietly rewrite. If it warns you, decide for yourself:

```powershell
powercfg /change standby-timeout-ac 0      # stay awake while plugged in
powercfg /change standby-timeout-ac 30     # put it back afterwards
```

A laptop that sleeps takes the relay down and disconnects every player.

---

## Stop-Relay.ps1

| Parameter | Default | What it does |
|---|---|---|
| `-Name` | `ghostshell` | Which relay to stop; match your `-Name` |
| `-Clean` | off | Also remove the firewall rule and the generated override file |
| `-RemoveImage` | off | Also delete the `ghostshell:1.0` image |

Plain `Stop-Relay.ps1` leaves the override and firewall rule in place so the
next start is fast. Use `-Clean` when the event is over. `-RemoveImage`
reclaims the disk, but the next start has to rebuild, which needs internet.

---

## Between groups

You do not need to stop and restart. Level content is baked into the image
and player home directories are read-only, so a restart is already a clean
slate:

```powershell
docker compose --project-name ghostshell restart
```

---

## Not on Windows?

These scripts are Windows-only. On macOS and Linux use the `make` targets
(`make up`, `make test`, `make down`) or the raw `docker compose` commands in
[RUNNING.md](../RUNNING.md).
