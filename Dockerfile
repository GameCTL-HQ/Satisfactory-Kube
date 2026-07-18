# GameCTL Satisfactory dedicated server image — built from scratch so GameCTL
# controls exactly what runs.
#
# Sources: Debian's official base and Valve's official steamcmd tarball. The
# game itself (~10GB, app 1690800, anonymous) is NOT baked — it installs to the
# persistent volume at /config/gamefiles on first boot and is update-checked on
# each start (SKIPUPDATE=false forces it). Baking 10GB into an image would make
# every update a full re-pull on every node; the volume cache keeps restarts
# instant and updates incremental.
FROM debian:12-slim

RUN dpkg --add-architecture i386 && apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl lib32gcc-s1 tini util-linux \
    && rm -rf /var/lib/apt/lists/*

# Valve's official steamcmd, owned by the run user (steamcmd writes to its
# own dir + $HOME).
RUN mkdir -p /opt/steamcmd && cd /opt/steamcmd \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar xz \
    && useradd -u 1000 -d /home/steam -m -s /usr/sbin/nologin steam \
    && mkdir -p /srv/satisfactory \
    && chown -R 1000:1000 /opt/steamcmd /srv/satisfactory

COPY entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

ENV CONFIG_DIR=/config \
    BRANCH=public \
    SKIPUPDATE=false \
    SERVERGAMEPORT=7777 \
    RELIABLEPORT=8888 \
    MULTIHOME=0.0.0.0 \
    UID=1000 \
    GID=1000

# 7777 game (tcp+udp), 8888 reliable messaging (tcp+udp).
EXPOSE 7777/udp 7777/tcp 8888/udp 8888/tcp
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
