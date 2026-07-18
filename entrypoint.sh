#!/usr/bin/env bash
# GameCTL Satisfactory entrypoint. The image bakes only Valve's steamcmd; the
# game installs/updates to the persistent volume at $CONFIG_DIR/gamefiles.
# Env contract keeps the wolveix-compatible names GameCTL's generator sends:
#   BRANCH (public|experimental), SKIPUPDATE, SERVERGAMEPORT, RELIABLEPORT,
#   MULTIHOME, XDG_CONFIG_HOME (saves are symlinked to /config/saved
#   regardless, so they always land on the volume).
set -euo pipefail

CFG="${CONFIG_DIR:-/config}"
uid="${UID:-1000}"; gid="${GID:-1000}"
branch="${BRANCH:-public}"
gameport="${SERVERGAMEPORT:-7777}"
reliableport="${RELIABLEPORT:-8888}"
multihome="${MULTIHOME:-0.0.0.0}"

GAMEDIR="$CFG/gamefiles"
mkdir -p "$GAMEDIR" "$CFG/saved" "$CFG/.steamhome"
export HOME="$CFG/.steamhome"
chown -R "$uid:$gid" "$CFG" 2>/dev/null || true

steamcmd_update() {
  local beta_args=()
  [ "$branch" = "experimental" ] && beta_args=(+app_update 1690800 -beta experimental validate) \
                                 || beta_args=(+app_update 1690800 validate)
  for i in 1 2 3 4 5; do
    /opt/steamcmd/steamcmd.sh +force_install_dir "$GAMEDIR" +login anonymous "${beta_args[@]}" +quit && return 0
    echo "gamectl: steamcmd attempt $i failed (cold-start config race); retrying" >&2
    sleep 10
  done
  return 1
}

need_install=0
[ -x "$GAMEDIR/FactoryServer.sh" ] || need_install=1
if [ "$need_install" = "1" ] || [ "$(echo "${SKIPUPDATE:-false}" | tr '[:upper:]' '[:lower:]')" != "true" ]; then
  echo "gamectl: installing/updating Satisfactory ($branch) into $GAMEDIR"
  steamcmd_update || { [ "$need_install" = "0" ] && echo "gamectl: WARN update failed, starting existing install" || { echo "ERROR: install failed" >&2; exit 1; }; }
else
  echo "gamectl: SKIPUPDATE=true — using existing install"
fi

# Saves: the server writes to $XDG_CONFIG_HOME (or ~/.config)/Epic/FactoryGame.
# Anchor that dir onto the volume at /config/saved so saves always persist.
xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
# The env may point somewhere unwritable for the run uid; fall back onto the
# volume (the Epic/FactoryGame symlink anchors saves to /config/saved anyway).
if ! mkdir -p "$xdg/Epic" 2>/dev/null; then
  echo "gamectl: WARN $xdg not writable — using $CFG/.steamhome/.config"
  xdg="$CFG/.steamhome/.config"
  mkdir -p "$xdg/Epic"
fi
if [ ! -L "$xdg/Epic/FactoryGame" ]; then
  rm -rf "$xdg/Epic/FactoryGame"
  ln -s "$CFG/saved" "$xdg/Epic/FactoryGame"
fi
export XDG_CONFIG_HOME="$xdg"

chown -R "$uid:$gid" "$CFG" 2>/dev/null || true

echo "gamectl: starting Satisfactory — game ${gameport}, reliable ${reliableport}, multihome ${multihome}"
cd "$GAMEDIR"
run=(./FactoryServer.sh -Port="$gameport" -ReliablePort="$reliableport" -multihome="$multihome" -unattended)
if [ "$(id -u)" = "0" ]; then
  exec setpriv --reuid "$uid" --regid "$gid" --clear-groups "${run[@]}"
else
  exec "${run[@]}"
fi
