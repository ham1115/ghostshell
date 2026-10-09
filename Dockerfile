# syntax=docker/dockerfile:1.7
# =====================================================================
#  GHOSTSHELL :: Relay Nine — self-contained terminal CTF
#
#  Build:  docker compose build
#  Run:    docker compose up -d
#  Play:   ssh level0@127.0.0.1 -p 2222      (password: ghostshell)
#
#  Requires BuildKit (default on Docker 23+). The provisioning script is
#  bind-mounted for the duration of one RUN instruction, so it is never
#  committed to an image layer and the keys cannot be recovered from the
#  image with `docker save` / `docker history`.
#
#  The parser directive above must stay on line 1 — a syntax directive
#  preceded by any comment is silently treated as a comment itself.
# =====================================================================

FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="GHOSTSHELL :: Relay Nine"
LABEL org.opencontainers.image.description="Self-contained SSH-based terminal CTF. No internet access required."
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=UTC

# ---------------------------------------------------------------------
# Tooling. Everything a player needs to finish the game is here; the
# container never needs network access at run time.
# ---------------------------------------------------------------------
# debian-slim suppresses man pages via a dpkg exclude list. The game is
# meant to be solvable with `man`, so the exclude list is removed first.
#   shell/login .... openssh-server bash coreutils util-linux login passwd
#   text ........... findutils grep sed gawk diffutils less
#   inspection ..... file binutils xxd bsdextrautils
#   archives ....... tar gzip bzip2 xz-utils zip unzip
#   net/scripting .. python3 curl netcat-openbsd iproute2 net-tools procps
#   conveniences ... nano vim-tiny tree jq bc man-db manpages
RUN rm -f /etc/dpkg/dpkg.cfg.d/docker /etc/dpkg/dpkg.cfg.d/excludes \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      openssh-server bash coreutils util-linux login passwd \
      findutils grep sed gawk diffutils less \
      file binutils xxd bsdextrautils \
      tar gzip bzip2 xz-utils zip unzip \
      python3 curl netcat-openbsd iproute2 net-tools procps psmisc \
      nano vim-tiny tree jq bc ca-certificates man-db manpages \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------
# sshd configuration, pre-auth banner, MOTD
# ---------------------------------------------------------------------
COPY sshd_config /etc/ssh/sshd_config
COPY motd /etc/motd
COPY banner /etc/ghostshell-banner
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Host keys are generated at first boot by the entrypoint, not baked in,
# and Debian's own pam_motd notices are removed so the intro stands alone.
RUN chmod 0644 /etc/ssh/sshd_config /etc/motd /etc/ghostshell-banner \
 && chmod 0755 /usr/local/bin/entrypoint.sh \
 && rm -f /etc/ssh/ssh_host_*_key* \
 && rm -f /etc/update-motd.d/* \
 && rm -f /etc/legal

# ---------------------------------------------------------------------
# Provision the levels. Bind-mounted, single layer, never shipped.
# ---------------------------------------------------------------------
RUN --mount=type=bind,source=setup_levels.sh,target=/tmp/setup_levels.sh \
    bash /tmp/setup_levels.sh

# ---------------------------------------------------------------------
# Final hardening sweep
# ---------------------------------------------------------------------
# /tmp (sticky) is the only player-writable location; the package
# manager is taken away from players so the image cannot be altered.
RUN install -d -m 0755 /run/sshd \
 && chmod 1777 /tmp \
 && chmod 0750 /usr/bin/apt /usr/bin/apt-get /usr/bin/dpkg || true

EXPOSE 2222
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD /bin/sh -c 'nc -z 127.0.0.1 2222 && nc -z 127.0.0.1 31337'

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
