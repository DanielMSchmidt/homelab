# CrowdSec + Auto-Upgrade — Design Spec

## Overview

Add two security improvements to the homelab:
1. **Auto-upgrade**: GitHub Action updates flake.lock nightly, NUC pulls and rebuilds at 4am
2. **CrowdSec**: Intrusion detection watching SSH and Caddy logs, with firewall bouncing

## Auto-Upgrade

### GitHub Action

New workflow `.github/workflows/update-flake.yml`:
- **Schedule**: Daily at 1:30am UTC (3:30am CEST — runs before 4am NUC upgrade)
- **Steps**: checkout → install Nix → `nix flake update` → commit and push `flake.lock` if changed
- **Branch**: `main`
- **No PR** — direct commit to main. This is a lock file update, not a code change.

### NUC Auto-Upgrade

New module `modules/auto-upgrade.nix`:

```nix
system.autoUpgrade = {
  enable = true;
  flake = "github:DanielMSchmidt/homelab";  # pulls from GitHub
  dates = "04:00";                            # daily at 4am local time
  allowReboot = true;
  rebootWindow = { lower = "04:00"; upper = "05:00"; };
};
```

- Rebuilds from the GitHub flake (which has the updated flake.lock from the Action)
- Only reboots during 4:00-5:00 window if a kernel update requires it
- Service restarts happen during `nixos-rebuild switch` (at 4am)
- Systemd services have `Restart=on-failure` by default — crashed services auto-restart
- Previous generations are kept. Manual rollback: `sudo nixos-rebuild switch --rollback`

## CrowdSec

New module `modules/crowdsec.nix`.

NixOS 24.11 has no built-in `services.crowdsec` module, but the packages `crowdsec` and `crowdsec-firewall-bouncer` are available. We write custom systemd services.

### Components

| Component | Package | Purpose |
|---|---|---|
| CrowdSec engine | `pkgs.crowdsec` | Parses logs, detects attacks, makes ban decisions |
| Firewall bouncer | `pkgs.crowdsec-firewall-bouncer` | Applies bans via nftables |

### Systemd Services

**crowdsec.service**:
- Runs the CrowdSec daemon
- Reads journald logs (SSH auth) and Caddy access logs
- Config at `/var/lib/crowdsec/config/`
- Data at `/var/lib/crowdsec/data/`

**crowdsec-firewall-bouncer.service**:
- Connects to CrowdSec local API (localhost:8080)
- Applies nftables ban rules for offending IPs
- Config at `/etc/crowdsec/bouncers/`
- Requires an API key (generated during first setup via `cscli bouncers add`)

### Initial Setup (post-deploy, one-time)

After first deploy, run on the NUC:
1. `sudo cscli collections install crowdsecurity/linux crowdsecurity/caddy` — install detection rules
2. `sudo cscli bouncers add firewall-bouncer` — generate API key for the bouncer
3. Write the API key to the bouncer config
4. `sudo systemctl restart crowdsec-firewall-bouncer`

This will be scripted in `scripts/setup-apps.sh`.

### Caddy Integration

Caddy needs access logging enabled for CrowdSec to parse. Add a global log directive in `modules/caddy.nix` that writes JSON access logs to a file CrowdSec can read.

### Log Sources

- **SSH**: journald (`sshd` unit) — detect brute-force login attempts
- **Caddy**: `/var/log/caddy/access.log` — detect web scanning, path traversal

## Files to Create/Modify

### New: `modules/auto-upgrade.nix`

- `system.autoUpgrade` configuration

### New: `modules/crowdsec.nix`

- Custom systemd service for CrowdSec engine
- Custom systemd service for firewall bouncer
- CrowdSec acquis (log source) configuration
- Bouncer configuration template
- Firewall rules

### New: `.github/workflows/update-flake.yml`

- Scheduled nix flake update + commit

### Modify: `hosts/nuc/default.nix`

- Import `auto-upgrade.nix` and `crowdsec.nix`

### Modify: `modules/caddy.nix`

- Enable JSON access logging to `/var/log/caddy/access.log`

### Modify: `scripts/setup-apps.sh`

- Add CrowdSec initial setup section (install collections, register bouncer)

### Modify: `modules/backup.nix`

- Add `/var/lib/crowdsec` to backup paths

## Testing

- Auto-upgrade: verify `system.autoUpgrade` evaluates in nix flake check
- CrowdSec: verify services start after deploy; test with `cscli metrics`
- GitHub Action: verify workflow runs and commits lock updates
