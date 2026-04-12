# Homelab

Declarative NixOS homelab running on an Intel NUC. Everything is defined in code -- fork this repo, customize, and deploy.

## What You Get

| Service | What It Does | Access |
|---|---|---|
| **AdGuard Home** | Blocks ads and malware at the DNS level | `http://adguard.home.lan` |
| **Home Assistant** | Home automation hub | `http://hass.home.lan` |
| **Caddy** | Reverse proxy -- gives services friendly URLs | Automatic |
| **Cloudflare Tunnel** | Secure remote access via your Cloudflare domain | `adguard.yourdomain.com`, `hass.yourdomain.com` |

## Prerequisites

- Intel NUC (or any x86_64 machine) with 8GB+ RAM
- USB drive (2GB+) for the NixOS installer
- A router where you can change the DNS server setting
- A domain managed by Cloudflare (for remote access)
- A computer to flash the USB and SSH from

## Quick Start

### 1. Fork and Customize

Fork this repo and edit `hosts/nuc/default.nix`:

```nix
# Set your NUC's static IP
networking.interfaces.eno1.ipv4.addresses = [{
  address = "192.168.1.50";  # <- your IP
  prefixLength = 24;
}];
networking.defaultGateway = "192.168.1.1";  # <- your router

# Set your timezone
time.timeZone = "America/New_York";  # <- your timezone

# Add your SSH public key
homelab.sshKeys = [
  "ssh-ed25519 AAAA... you@laptop"  # <- your key
];

# Your Cloudflare-managed domain
homelab.domain = "yourdomain.com";  # <- your domain
```

If your NUC uses an NVMe drive instead of SATA, also update `hosts/nuc/disk.nix`:

```nix
device = lib.mkDefault "/dev/nvme0n1";  # default is /dev/sda
```

### 2. Create a Cloudflare Tunnel

Before installing, create a tunnel so you have the credentials ready:

```bash
# Install cloudflared on your laptop
brew install cloudflare/cloudflare/cloudflared  # macOS
# or: nix-shell -p cloudflared

# Login to Cloudflare
cloudflared tunnel login

# Create the tunnel
cloudflared tunnel create homelab

# Note the credentials file path (e.g., ~/.cloudflared/<uuid>.json)
# You'll need this during the setup script

# Create DNS records pointing to the tunnel
cloudflared tunnel route dns homelab adguard.yourdomain.com
cloudflared tunnel route dns homelab hass.yourdomain.com
```

### 3. Flash NixOS

Download the [NixOS minimal ISO](https://nixos.org/download#nixos-iso) and flash it to a USB drive:

```bash
# macOS
sudo dd if=nixos-minimal-*.iso of=/dev/diskN bs=4M status=progress

# Linux
sudo dd if=nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress
```

### 4. Boot and Install

1. Plug the USB into the NUC and boot from it
2. Once booted, connect to your network (Ethernet recommended)
3. Find the NUC's IP: `ip addr`
4. From your laptop, SSH in: `ssh nixos@<nuc-ip>` (password is empty on the live ISO)
5. Clone your fork:

```bash
sudo su
nix-env -iA nixos.git
git clone https://github.com/YOUR_USER/homelab.git /tmp/homelab
cd /tmp/homelab
```

6. Run the setup script:

```bash
bash scripts/setup.sh
```

The script will:
- Ask which disk to use and partition it
- Generate hardware config for your specific NUC
- Optionally copy your Cloudflare Tunnel credentials
- Install NixOS

7. Remove the USB drive and reboot

### 5. Post-Boot Setup

After the NUC reboots:

1. **AdGuard Home**: Visit `http://<nuc-ip>:3000` and complete the setup wizard (set admin password, configure filters)
2. **Home Assistant**: Visit `http://<nuc-ip>:8123` and create your account
3. **Router DNS**: Set your router's DNS server to the NUC's IP. All devices on your network now get ad blocking.
4. **Cloudflare Tunnel** (if you skipped during setup): Copy the credentials JSON to `/etc/nixos/secrets/cloudflared-tunnel.json` on the NUC and restart the service

### 6. Set Up Nice URLs (Optional)

Once AdGuard Home is running, add DNS rewrites so you can use `adguard.home.lan` instead of IP addresses on your local network:

1. Open AdGuard Home at `http://<nuc-ip>:3000`
2. Go to **Filters -> DNS rewrites**
3. Add a rewrite: `*.home.lan` -> `<nuc-ip>` (e.g., `192.168.1.50`)

Now you can access locally:
- `http://adguard.home.lan` -> AdGuard Home
- `http://hass.home.lan` -> Home Assistant

Remotely (via Cloudflare Tunnel):
- `https://adguard.yourdomain.com` -> AdGuard Home
- `https://hass.yourdomain.com` -> Home Assistant

## Day-to-Day Usage

### Making Changes

Edit the Nix config on your laptop, then deploy:

```bash
# Enter the dev environment (gives you colmena, nil, nixpkgs-fmt)
nix develop

# Edit a module
vim modules/adguard.nix

# Deploy to the NUC
./deploy.sh
```

### Rolling Back

If a deployment breaks something, SSH into the NUC:

```bash
sudo nixos-rebuild switch --rollback
```

Or select a previous generation from the boot menu at startup. NixOS keeps all previous configurations in the bootloader.

### Adding Services

1. Create a new module: `modules/myservice.nix`
2. Import it in `hosts/nuc/default.nix`
3. Add a Caddy virtual host in `modules/caddy.nix`
4. Optionally add a Cloudflare Tunnel ingress in `modules/cloudflared.nix`
5. Deploy: `./deploy.sh`

## Testing

Tests run as NixOS VMs -- they boot a real (virtual) NixOS system and verify services work.

```bash
# Run on a Linux machine or in CI:
nix flake check                                              # all checks
nix build .#checks.x86_64-linux.adguard --print-build-logs   # single test
nix build .#checks.x86_64-linux.integration --print-build-logs  # full stack
```

CI runs all tests automatically on every push and PR.

## Secrets

This repo contains **zero secrets**. Sensitive data lives only on the NUC:

| Secret | Location on NUC | How It Gets There |
|---|---|---|
| Cloudflare Tunnel credentials | `/etc/nixos/secrets/cloudflared-tunnel.json` | Setup script or manual copy |
| Cloudflare origin cert | `/etc/nixos/secrets/cloudflared-cert.pem` | Setup script or manual copy |
| Restic backup password | `/etc/nixos/secrets/restic-password` | Auto-generated, **save in password manager** |
| AdGuard admin password | AdGuard Home's own database | Setup wizard on first boot |
| Home Assistant account | Home Assistant's own database | Setup wizard on first boot |

## Backups

Restic backs up service data to the USB stick (`/mnt/backup`) daily at 3am. Retention: 7 daily, 4 weekly, 6 monthly snapshots.

**What's backed up:**
- `/var/lib/AdGuardHome` — AdGuard Home config, filter lists, query logs
- `/var/lib/hass` — Home Assistant config, automations, database
- `/etc/nixos/secrets` — Cloudflare credentials, restic password, certs

### Check backup status

```bash
# List snapshots
ssh nuc 'sudo restic -r /mnt/backup/restic --password-file /etc/nixos/secrets/restic-password snapshots'

# Run a backup manually
ssh nuc 'sudo systemctl start restic-backups-usb.service'
```

### Restore from backup (full reinstall)

If you need to set up the NUC from scratch and restore from the USB backup:

1. **Install NixOS** as normal (boot from USB, run `scripts/setup.sh`)

2. **Reboot into the installed system** and SSH in: `ssh nuc`

3. **Restore secrets from 1Password** (if you used `secrets-to-op.sh`):
   ```bash
   eval $(op signin)
   bash scripts/secrets-from-op.sh
   ```
   This restores restic password, Cloudflare credentials, and certs. Skip to step 5.

   If you don't use 1Password, continue manually:

4. **Mount the backup USB** (should auto-mount, verify with `mount | grep backup`)

5. **List available snapshots:**
   ```bash
   sudo restic -r /mnt/backup/restic --password-file /etc/nixos/secrets/restic-password snapshots
   ```

6. **Stop services before restoring:**
   ```bash
   sudo systemctl stop home-assistant adguardhome
   ```

7. **Restore the data:**
   ```bash
   # Restore everything from the latest snapshot
   sudo restic -r /mnt/backup/restic --password-file /etc/nixos/secrets/restic-password restore latest --target /

   # Or restore a specific snapshot (use ID from step 5)
   sudo restic -r /mnt/backup/restic --password-file /etc/nixos/secrets/restic-password restore <snapshot-id> --target /
   ```

   This restores files to their original paths:
   - `/var/lib/AdGuardHome` — AdGuard skips the setup wizard, keeps your filters and settings
   - `/var/lib/hass` — Home Assistant keeps your automations, integrations, and history
   - `/etc/nixos/secrets` — Cloudflare Tunnel credentials and certs are restored

8. **Restart services:**
   ```bash
   sudo systemctl start adguardhome home-assistant
   ```

9. **Verify** — open AdGuard Home and Home Assistant in your browser. Your settings, accounts, and data should all be there.

### 1Password integration (recommended)

Store all secrets in 1Password so a fresh install can pull them automatically:

```bash
# After initial setup — store secrets from NUC into 1Password
eval $(op signin)
bash scripts/secrets-to-op.sh

# During a fresh install — restore secrets from 1Password to NUC
eval $(op signin)
bash scripts/secrets-from-op.sh
```

If you don't use 1Password, save the restic password manually:

```bash
ssh nuc 'sudo cat /etc/nixos/secrets/restic-password'
```

**Save it in your password manager.** Without it, the backup is encrypted and unrecoverable.

## Repository Structure

```
flake.nix              # Entry point -- inputs, host config, deployment, tests
hosts/nuc/
  default.nix          # NUC config -- customize this for your setup
  hardware.nix         # Hardware-specific (generated during setup)
  disk.nix             # Disk partitioning layout
modules/
  common.nix           # Base system: SSH, users, firewall, packages
  adguard.nix          # AdGuard Home DNS blocking
  caddy.nix            # Caddy reverse proxy
  home-assistant.nix   # Home Assistant automation
  cloudflared.nix      # Cloudflare Tunnel for remote access
  homepage.nix         # Homepage dashboard
  backup.nix           # Restic backups to USB stick
tests/
  adguard-test.nix     # VM test: DNS + web UI
  caddy-test.nix       # VM test: proxy routing
  integration-test.nix # VM test: all services together
scripts/
  setup.sh             # Bootstrap from NixOS live USB
  setup-apps.sh        # Create AdGuard Home + Home Assistant accounts, store in 1Password
  secrets-to-op.sh     # Store all secrets in 1Password
  secrets-from-op.sh   # Restore secrets from 1Password to NUC
  restore-backup.sh    # Restore service data from restic USB backup
deploy.sh              # Deploy changes from laptop
```

## License

MIT
