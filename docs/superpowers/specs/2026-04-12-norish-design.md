# Norish Recipe App — Design Spec

## Overview

Add [Norish](https://github.com/norish-recipes/norish), a self-hosted recipe manager, to the homelab. Norish runs as 4 OCI containers managed by Podman, integrated into the existing NixOS infrastructure (Caddy, Cloudflare Tunnel, AdGuard DNS, Homepage, backups, 1Password).

## Decisions

- **Runtime**: Podman OCI containers via `virtualisation.oci-containers` (no Docker daemon)
- **Access**: Local (`http://norish.home.lan`) + external via Cloudflare Tunnel (`https://norish.danielmschmidt.de`)
- **Auth**: Password auth (first user becomes admin)
- **Host port**: 8083 (3000 = AdGuard, 8082 = Homepage)

## Architecture

### Containers

All 4 containers share a `norish` Podman network. Only the app container exposes a port to the host.

| Container | Image | Host Port | Purpose |
|---|---|---|---|
| `norish` | `norishapp/norish:latest` | 8083:3000 | Main app (Node.js) |
| `norish-db` | `postgres:17-alpine` | none | PostgreSQL database |
| `norish-redis` | `redis:8.6.0` | none | Real-time events + job queues |
| `norish-chrome` | `zenika/alpine-chrome:latest` | none | Headless Chrome for recipe scraping |

### Environment Variables (norish container)

| Variable | Value |
|---|---|
| `DATABASE_URL` | `postgres://norish:norish@norish-db:5432/norish` |
| `REDIS_URL` | `redis://norish-redis:6379` |
| `CHROME_WS_ENDPOINT` | `ws://norish-chrome:3000` |
| `AUTH_URL` | `https://norish.danielmschmidt.de` |
| `MASTER_KEY` | Loaded from `/etc/nixos/secrets/norish-master-key` |

The `MASTER_KEY` is loaded via `environmentFiles` pointing to `/etc/nixos/secrets/norish-env` which contains `MASTER_KEY=<value>`. This avoids putting the secret in the Nix store.

### Podman Network

A systemd oneshot service `podman-norish-network` creates the network before any container starts. All container services depend on it via `after`/`requires`.

### Chrome Headless

The chrome container needs:
- `--no-sandbox` flag
- `shm_size: 256m` (or equivalent tmpfs mount)
- Runs a CDP server on port 3000 (internal to the podman network)

## Files to Create/Modify

### New: `modules/norish.nix`

Contains:
- `virtualisation.podman.enable = true`
- Systemd oneshot for `norish` podman network
- 4 OCI container definitions with inter-container dependencies
- Bind mount directories created via `systemd.tmpfiles.rules`
- Firewall: TCP 8083

### Modify: `hosts/nuc/default.nix`

Add import: `../../modules/norish.nix`

### Modify: `modules/caddy.nix`

Add virtual host:
```
http://norish.home.lan → localhost:8083
```

### Modify: `modules/cloudflared.nix`

Add ingress rule:
```
"norish.${config.homelab.domain}" = "http://localhost:8083";
```

### Modify: `modules/adguard.nix`

Add DNS rewrite:
```nix
{ domain = "norish.${domain}"; answer = nucIp; }
```

### Modify: `modules/homepage.nix`

Add service card:
```nix
{
  "Norish" = {
    icon = "mdi-food-apple"; # MDI icon — norish has no Homepage icon
    href = "https://norish.${domain}";
    description = "Recipe manager";
  };
}
```

### Modify: `modules/backup.nix`

Add path: `/var/lib/norish` (covers postgres data, uploads, redis data)

### Modify: `scripts/setup-apps.sh`

Add section to:
1. Generate `MASTER_KEY` via `openssl rand -base64 32`
2. Write env file to `/etc/nixos/secrets/norish-env` (`MASTER_KEY=<value>`)
3. Create 1Password item `Homelab - Norish` with the master key

### Modify: `scripts/secrets-to-op.sh`

Fetch and store norish master key from NUC to 1Password.

### Modify: `scripts/secrets-from-op.sh`

Restore norish master key from 1Password to NUC.

### Modify: `tests/integration-test.nix`

Add norish import and basic connectivity test (curl health endpoint). Note: OCI container tests may need special handling in NixOS VM tests — if Podman doesn't work in the test VM, validate via flake eval only (same approach as cloudflared).

## Data Persistence

Bind mounts under `/var/lib/norish/`:

| Path | Container Mount | Purpose |
|---|---|---|
| `/var/lib/norish/postgres` | `/var/lib/postgresql/data` | Database |
| `/var/lib/norish/uploads` | `/app/uploads` | Recipe images/media |
| `/var/lib/norish/redis` | `/data` | Redis persistence |

Directories created via `systemd.tmpfiles.rules` with appropriate ownership (norish app runs as UID 1000).

## Secret Management

- **Generation**: `openssl rand -base64 32` → written to `/etc/nixos/secrets/norish-env` as `MASTER_KEY=<value>`
- **1Password**: Stored in `Homelab - Norish` item via `setup-apps.sh`
- **Backup**: Covered by existing restic backup of `/etc/nixos/secrets`
- **Restore**: `secrets-from-op.sh` pulls from 1Password and writes to NUC

## DNS

Two entries resolve to the NUC:
- `norish.home.lan` — via AdGuard wildcard `*.home.lan` (already exists)
- `norish.danielmschmidt.de` — explicit AdGuard rewrite (new)

## Post-Deploy Setup

After first deploy:
1. `setup-apps.sh` generates the master key and stores in 1Password
2. Visit `https://norish.danielmschmidt.de`
3. Create first account (becomes admin)
4. Registration auto-disables after first signup
5. Configure AI providers, video parsing etc. via Settings > Admin in the UI
