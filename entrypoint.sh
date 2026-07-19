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
echo "gamectl: entrypoint starting (config: $CFG)"
mkdir -p "$GAMEDIR" "$CFG/saved" "$CFG/.steamhome"
export HOME="$CFG/.steamhome"
# No recursive chown: crawling a ~15GB NFS tree stalls boot for minutes and
# the server only needs write on the mutable paths.
chown "$uid:$gid" "$CFG" "$CFG/saved" 2>/dev/null || true
# Fix ownership of files dropped onto the share as root (e.g. an operator
# scp'ing in saves/worlds) — kubelet does not apply fsGroup to NFS volumes,
# and root-owned data files can break the server in silent ways (see
# Necesse-Kube d4b719f). Only touches mismatched files; the steamcmd install
# tree is pruned (large, root-managed, read-only for the run user).
find "$CFG" \( -path "$CFG/gamefiles" -o -path "$CFG/.steamhome" \) -prune -o ! -user "$uid" -exec chown "$uid:$gid" {} + 2>/dev/null || true

steamcmd_update() {
  local beta_args=()
  [ "$branch" = "experimental" ] && beta_args=(+app_update 1690800 -beta experimental validate) \
                                 || beta_args=(+app_update 1690800 validate)
  for i in 1 2 3 4 5 6; do
    /opt/steamcmd/steamcmd.sh +force_install_dir "$GAMEDIR" +login anonymous "${beta_args[@]}" +quit && return 0
    echo "gamectl: steamcmd attempt $i failed — clearing appcache and retrying" >&2
    # "Missing configuration" sticks when the persisted appinfo cache is
    # poisoned; clear it (and after repeated failures, all steam state —
    # the game install in $GAMEDIR is untouched, only re-validated).
    rm -rf "$HOME/Steam/appcache" 2>/dev/null || true
    [ "$i" -ge 4 ] && { echo "gamectl: resetting steam state in $HOME" >&2; rm -rf "$HOME/Steam" 2>/dev/null || true; }
    sleep 10
  done
  return 1
}

need_install=0
[ -x "$GAMEDIR/FactoryServer.sh" ] || need_install=1
if [ "$need_install" = "1" ] || [ "$(echo "${SKIPUPDATE:-true}" | tr '[:upper:]' '[:lower:]')" != "true" ]; then
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

echo "gamectl: starting Satisfactory — game ${gameport}, reliable ${reliableport}, multihome ${multihome}"
cd "$GAMEDIR"
run=(./FactoryServer.sh -Port="$gameport" -ReliablePort="$reliableport" -multihome="$multihome" -unattended)
if [ "$(id -u)" = "0" ]; then
  exec setpriv --reuid "$uid" --regid "$gid" --clear-groups "${run[@]}"
else
  exec "${run[@]}"
fi
