# Minecraft Server for Nintendo Switch (Bedrock) — Design Spec

## Overview

Add a Minecraft server to the homelab NUC that supports Nintendo Switch (Bedrock Edition) clients, accessible both on LAN and remotely via playit.gg.

## Architecture

```
Switch (Bedrock) ──UDP──→ playit.gg cloud ──UDP──→ playit agent (:19132)
                                                        │
                                                   GeyserMC (:19132)
                                                        │
                                                   Java Server (:25565)
```

Three systemd services in one `modules/minecraft.nix`:

1. **Java Minecraft Server** — NixOS built-in `services.minecraft-server` module, TCP 25565 (localhost only)
2. **GeyserMC standalone** — custom systemd service, translates Bedrock (UDP 19132) → Java (TCP 25565)
3. **playit.gg agent** — custom systemd service, tunnels UDP 19132 to the internet for remote access

## Components

### 1. Java Minecraft Server

- Uses the NixOS `services.minecraft-server` module
- Memory: 4GB (`-Xmx4G -Xms4G`) — NUC has 32GB total
- Whitelist enabled, configured declaratively in Nix
- EULA accepted in Nix config
- Data directory: `/var/lib/minecraft` (NixOS default)
- Listens on `localhost:25565` only (not exposed to network directly)
- Default game settings: survival mode, normal difficulty (changeable via `server-properties`)
- `online-mode = false` required for GeyserMC to proxy Bedrock players (Geyser handles auth)

### 2. GeyserMC Standalone Proxy

- Standalone JAR fetched via `pkgs.fetchurl` (pinned version + hash)
- Nix-generated `config.yml` pointing to `localhost:25565`
- Listens on `0.0.0.0:19132` (UDP) for Bedrock clients
- Runs as a custom systemd service under a dedicated `geyser` system user
- Requires Java runtime (`pkgs.jre_headless`)
- Data directory: `/var/lib/geyser`
- Depends on `minecraft-server.service` (systemd `after` + `requires`)
- `auth-type: online` — requires Xbox Live authentication for Bedrock players (prevents unauthorized access)

### 3. playit.gg Agent

- Static Linux binary fetched via `pkgs.fetchurl` (pinned version + hash)
- Requires a secret token for tunnel authentication
- Token stored in `/etc/nixos/secrets/playit-secret.toml` (follows existing secrets pattern)
- Runs as a custom systemd service under a dedicated system user
- Depends on GeyserMC service being up
- Outbound connection only — no firewall ports needed for remote access

## Integration with Existing Services

### Files to Modify

| File | Change |
|------|--------|
| `modules/minecraft.nix` | **New** — Java server + GeyserMC + playit.gg agent |
| `hosts/nuc/default.nix` | Add `./modules/minecraft.nix` to imports |
| `modules/homepage.nix` | Add Minecraft card to dashboard |
| `modules/adguard.nix` | Add `minecraft.home.lan` DNS rewrite → NUC IP |
| `modules/backup.nix` | Add `/var/lib/minecraft` and `/var/lib/geyser` to backup paths |

### Services NOT Modified

- **Caddy** — Minecraft doesn't use HTTP, no reverse proxy needed
- **Cloudflared** — playit.gg handles remote access (Cloudflare tunnels can't proxy UDP)
- **CrowdSec** — no HTTP logs to monitor for this service

### Firewall

- Open UDP 19132 for LAN Bedrock play
- TCP 25565 stays localhost-only (no firewall rule needed)
- playit.gg agent uses outbound connections only

### DNS (AdGuard)

- Add rewrite: `minecraft.home.lan` → NUC IP (for convenient LAN server discovery)

### Backup (Restic)

- Add `/var/lib/minecraft` (world data, server config)
- Add `/var/lib/geyser` (Geyser config and cache)

### Homepage Dashboard

- Add a Minecraft card showing server status

## Secrets

| Secret | File | How Created |
|--------|------|-------------|
| playit.gg token | `/etc/nixos/secrets/playit-secret.toml` | Sign up at playit.gg, create UDP tunnel, save token |

## Post-Deploy Setup (One-Time)

1. Sign up at [playit.gg](https://playit.gg)
2. Create a UDP tunnel pointing to port 19132
3. Save the secret/token to `/etc/nixos/secrets/playit-secret.toml` on the NUC
4. Deploy: `./deploy.sh`
5. On Switch: add server with the playit.gg public address
6. Add player gamertags to the whitelist in `modules/minecraft.nix`

## Resource Estimates

- **RAM:** ~4.5GB total (4GB Java server + ~256MB GeyserMC + ~16MB playit agent)
- **Disk:** ~1GB initially (server JAR + world data), grows with world exploration
- **CPU:** Low idle, moderate during play (Java server is the main consumer)
