# Satisfactory-Kube

A from-scratch **Satisfactory dedicated server** image for Kubernetes,
maintained by [GameCTL](https://github.com/GameCTL-HQ/GameCTL). Sources:
Debian's official base + Valve's official steamcmd. The game (~10GB, app
`1690800`, anonymous) is **not baked** — it installs to the persistent volume
at `/config/gamefiles` on first boot and is update-checked each start
(`SKIPUPDATE=true` to skip). Saves are anchored to `/config/saved` via an
`XDG_CONFIG_HOME` symlink, wolveix-compatible layout — existing volumes
migrate as-is.

`ghcr.io/gamectl-hq/satisfactory-kube:latest`

| Var | Default | Notes |
|-----|---------|-------|
| `BRANCH` | `public` | or `experimental` |
| `SKIPUPDATE` | `false` | `true` = skip steamcmd check (auto-installs if missing) |
| `SERVERGAMEPORT` / `RELIABLEPORT` | `7777` / `8888` | tcp+udp each |
| `MULTIHOME` | `0.0.0.0` | Bind address |
| `UID`/`GID` | `1000` | Unprivileged |
