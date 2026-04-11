# NixOS Homelab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fully declarative NixOS homelab on an Intel NUC with DNS blocking, home automation, reverse proxy, VPN, remote deployment, VM-based testing, and CI.

**Architecture:** NixOS flake with modular per-service configs. Colmena deploys from laptop to NUC over SSH. NixOS VM tests validate services in QEMU. GitHub Actions runs checks on every push.

**Tech Stack:** NixOS 24.11, Nix Flakes, Colmena, disko, AdGuard Home, Home Assistant, Caddy, Tailscale

**Spec:** `docs/superpowers/specs/2026-04-12-nixos-homelab-design.md`

**Dev notes:**
- Developer is on macOS (aarch64-darwin). VM tests only run on x86_64-linux (CI or on the NUC).
- Local validation on Mac: `nix flake show` to check structure. Full `nix flake check` runs in CI.
- The repo uses a "fork and customize" model — all config is tracked in git with sensible defaults. Users fork and edit `hosts/nuc/default.nix` for their setup. No gitignored config files.
- On-device secrets (Tailscale auth key) go in `/etc/nixos/secrets/` on the NUC, never in the repo.

---

## File Map

```
homelab/
├── flake.nix                         # Flake entry point: inputs, nixosConfigurations, colmena, checks, devShell
├── .gitignore                        # result, .direnv
├── hosts/nuc/
│   ├── default.nix                   # NUC host config: imports modules, sets hostname/networking defaults
│   ├── hardware.nix                  # Placeholder — replaced by nixos-generate-config during setup
│   └── disk.nix                      # Disko declarative disk partitioning
├── modules/
│   ├── common.nix                    # Base system: SSH, users, locale, firewall, nix settings, base packages
│   ├── adguard.nix                   # AdGuard Home: DNS blocking + firewall rules
│   ├── caddy.nix                     # Caddy: reverse proxy with virtual hosts for all services
│   ├── home-assistant.nix            # Home Assistant: home automation
│   └── cloudflared.nix               # Cloudflare Tunnel: remote access via Cloudflare edge
├── tests/
│   ├── adguard-test.nix              # VM test: DNS resolution + web UI
│   ├── caddy-test.nix                # VM test: reverse proxy routing
│   └── integration-test.nix          # VM test: full stack — all services boot and respond
├── scripts/
│   └── setup.sh                      # Bootstrap: partition, configure secrets, install NixOS
├── deploy.sh                         # Thin wrapper: colmena apply
├── .github/workflows/check.yml       # CI: flake check + VM tests
└── README.md                         # Complete guide: bare NUC → running homelab
```

---

### Task 1: Flake Scaffolding + Base System

**Files:**
- Create: `flake.nix`
- Create: `.gitignore`
- Create: `hosts/nuc/default.nix`
- Create: `hosts/nuc/hardware.nix`
- Create: `hosts/nuc/disk.nix`
- Create: `modules/common.nix`

This task creates the full skeleton. After this, `nix flake show` succeeds and the NixOS config evaluates.

- [ ] **Step 1: Create `.gitignore`**

```gitignore
result
.direnv
```

- [ ] **Step 2: Create `modules/common.nix`**

Base system config shared across all hosts.

```nix
{ config, lib, pkgs, ... }:
{
  # Custom option: SSH keys used across the system
  options.homelab.sshKeys = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "SSH public keys for the admin user.";
  };

  # When mixing options and config in a module, config must be explicit
  config = {
    # Nix settings
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    # Locale and timezone — override in hosts/nuc/default.nix
    time.timeZone = lib.mkDefault "UTC";
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

    # SSH hardened defaults
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # Admin user — add your SSH public key in hosts/nuc/default.nix
    users.users.admin = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = config.homelab.sshKeys;
    };

    # Allow admin to sudo without password (convenience for single-user homelab)
    security.sudo.wheelNeedsPassword = false;

    # Base firewall — individual modules add their own ports
    networking.firewall.enable = true;

    # Essential packages
    environment.systemPackages = with pkgs; [
      vim
      git
      htop
      curl
    ];
  };
}
```

- [ ] **Step 3: Create `hosts/nuc/disk.nix`**

Declarative disk layout for disko. Uses GPT with an EFI system partition and an ext4 root.

```nix
{ lib, ... }:
{
  disko.devices = {
    disk.main = {
      # Change to match your NUC's drive: /dev/nvme0n1 for NVMe, /dev/sda for SATA
      device = lib.mkDefault "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          esp = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
```

- [ ] **Step 4: Create `hosts/nuc/hardware.nix`**

Placeholder that makes the config evaluate. Replaced by `nixos-generate-config` during setup.

```nix
# PLACEHOLDER — replaced during setup by nixos-generate-config
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
```

- [ ] **Step 5: Create `hosts/nuc/default.nix`**

The NUC's top-level config. Imports all modules. Contains customizable values near the top.

```nix
{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./disk.nix
    ../../modules/common.nix
  ];

  # ============================================================
  # CUSTOMIZE THESE VALUES FOR YOUR SETUP
  # ============================================================

  networking.hostName = "nuc";

  # Static IP — change to match your LAN
  networking.interfaces.eno1.ipv4.addresses = [{
    address = "192.168.1.50";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.1.1";
  networking.nameservers = [ "127.0.0.1" ];

  time.timeZone = "America/New_York";

  # Add your SSH public key(s) here
  homelab.sshKeys = [
    # "ssh-ed25519 AAAA... you@laptop"
  ];

  # ============================================================

  system.stateVersion = "24.11";
}
```

- [ ] **Step 6: Create `flake.nix`**

Entry point. Defines inputs, the NUC host, Colmena deployment, test checks, and a dev shell with tooling.

```nix
{
  description = "NixOS homelab on Intel NUC";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, ... }:
  let
    linuxSystem = "x86_64-linux";
    linuxPkgs = import nixpkgs { system = linuxSystem; };
    forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
  in
  {
    nixosConfigurations.nuc = nixpkgs.lib.nixosSystem {
      system = linuxSystem;
      modules = [
        disko.nixosModules.disko
        ./hosts/nuc
      ];
    };

    colmena = {
      meta = {
        nixpkgs = linuxPkgs;
      };
      nuc = {
        deployment = {
          targetHost = "nuc";
          targetUser = "admin";
          buildOnTarget = true;
        };
        imports = [
          disko.nixosModules.disko
          ./hosts/nuc
        ];
      };
    };

    # Tests — added in later tasks
    checks.${linuxSystem} = {};

    devShells = forAllSystems (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        default = pkgs.mkShell {
          packages = with pkgs; [
            colmena
            nil
            nixpkgs-fmt
          ];
        };
      }
    );
  };
}
```

- [ ] **Step 7: Verify and commit**

Run: `nix flake show`

Expected output shows `nixosConfigurations.nuc`, `colmena`, `devShells`, and `checks` attributes.

```bash
git add flake.nix .gitignore hosts/ modules/
git commit -m "feat: scaffold flake with base system config"
```

---

### Task 2: AdGuard Home Module + Test

**Files:**
- Create: `modules/adguard.nix`
- Create: `tests/adguard-test.nix`
- Modify: `hosts/nuc/default.nix` (add import)
- Modify: `flake.nix` (add check)

- [ ] **Step 1: Write the VM test**

```nix
# tests/adguard-test.nix
# Function form so pkgs is in scope for testScript interpolation
{ pkgs, ... }:
{
  name = "adguard";

  nodes.machine = { ... }: {
    imports = [ ../modules/adguard.nix ];
    networking.firewall.enable = true;
  };

  testScript = ''
    machine.wait_for_unit("adguardhome.service")
    machine.wait_for_open_port(3000)

    # Web UI responds
    machine.succeed("curl -sf http://localhost:3000")

    # DNS responds to queries
    machine.succeed("${pkgs.dnsutils}/bin/dig @127.0.0.1 example.com +short +timeout=5")
  '';
}
```

- [ ] **Step 2: Wire the test into flake.nix**

Replace the empty `checks` in `flake.nix`:

```nix
    checks.${linuxSystem} = {
      adguard = linuxPkgs.nixosTest (import ./tests/adguard-test.nix);
    };
```

- [ ] **Step 3: Write the AdGuard Home module**

```nix
# modules/adguard.nix
{ config, lib, ... }:
{
  services.adguardhome = {
    enable = true;
    mutableSettings = true;
    settings = {
      http.address = "0.0.0.0:3000";
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [
          "1.1.1.1"
          "9.9.9.9"
          "8.8.8.8"
        ];
      };
    };
  };

  networking.firewall = {
    allowedTCPPorts = [ 53 3000 ];
    allowedUDPPorts = [ 53 ];
  };
}
```

- [ ] **Step 4: Import the module in host config**

Add to the `imports` list in `hosts/nuc/default.nix`:

```nix
  imports = [
    ./hardware.nix
    ./disk.nix
    ../../modules/common.nix
    ../../modules/adguard.nix
  ];
```

- [ ] **Step 5: Verify and commit**

Run: `nix flake show` (verify adguard check appears under `checks.x86_64-linux`)

```bash
git add modules/adguard.nix tests/adguard-test.nix hosts/nuc/default.nix flake.nix
git commit -m "feat: add AdGuard Home module with DNS blocking and VM test"
```

---

### Task 3: Caddy Module + Test

**Files:**
- Create: `modules/caddy.nix`
- Create: `tests/caddy-test.nix`
- Modify: `hosts/nuc/default.nix` (add import)
- Modify: `flake.nix` (add check)

- [ ] **Step 1: Write the VM test**

The test spins up a dummy HTTP backend and verifies Caddy proxies to it by hostname.

```nix
# tests/caddy-test.nix
{ pkgs, ... }:
{
  name = "caddy";

  nodes.machine = { pkgs, ... }: {
    imports = [ ../modules/caddy.nix ];

    # Dummy backend on port 8080 to proxy to
    systemd.services.dummy-backend = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        ${pkgs.python3}/bin/python3 -c "
        from http.server import HTTPServer, BaseHTTPRequestHandler
        class H(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'dummy-ok')
        HTTPServer(('127.0.0.1', 8080), H).serve_forever()
        "
      '';
    };

    # Override caddy config to proxy test.home.lan → dummy backend
    services.caddy.virtualHosts."http://test.home.lan".extraConfig = ''
      reverse_proxy localhost:8080
    '';

    # Fake DNS: resolve test.home.lan to localhost
    networking.hosts."127.0.0.1" = [ "test.home.lan" ];
  };

  testScript = ''
    machine.wait_for_unit("caddy.service")
    machine.wait_for_unit("dummy-backend.service")
    machine.wait_for_open_port(80)

    # Caddy proxies based on Host header
    output = machine.succeed("curl -sf -H 'Host: test.home.lan' http://127.0.0.1")
    assert "dummy-ok" in output, f"Expected 'dummy-ok', got: {output}"
  '';
}
```

- [ ] **Step 2: Write the Caddy module**

```nix
# modules/caddy.nix
{ config, lib, ... }:
{
  services.caddy = {
    enable = true;

    virtualHosts."http://adguard.home.lan".extraConfig = ''
      reverse_proxy localhost:3000
    '';

    virtualHosts."http://hass.home.lan".extraConfig = ''
      reverse_proxy localhost:8123
    '';
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

- [ ] **Step 3: Add import and wire test**

Add to `hosts/nuc/default.nix` imports:

```nix
    ../../modules/caddy.nix
```

Add to `flake.nix` checks:

```nix
      caddy = linuxPkgs.nixosTest (import ./tests/caddy-test.nix);
```

- [ ] **Step 4: Verify and commit**

Run: `nix flake show`

```bash
git add modules/caddy.nix tests/caddy-test.nix hosts/nuc/default.nix flake.nix
git commit -m "feat: add Caddy reverse proxy module with VM test"
```

---

### Task 4: Home Assistant Module

**Files:**
- Create: `modules/home-assistant.nix`
- Modify: `hosts/nuc/default.nix` (add import)

No standalone VM test — Home Assistant is slow to start and tested in the integration test.

- [ ] **Step 1: Write the Home Assistant module**

```nix
# modules/home-assistant.nix
{ config, lib, pkgs, ... }:
{
  services.home-assistant = {
    enable = true;
    config = {
      homeassistant = {
        name = "Home";
        unit_system = "metric";
        time_zone = config.time.timeZone;
      };
      # Trust Caddy reverse proxy
      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" "::1" ];
      };
      # Load default integrations
      default_config = {};
    };
  };

  networking.firewall.allowedTCPPorts = [ 8123 ];
}
```

- [ ] **Step 2: Add import to host config**

Add to `hosts/nuc/default.nix` imports:

```nix
    ../../modules/home-assistant.nix
```

- [ ] **Step 3: Verify and commit**

Run: `nix flake show`

```bash
git add modules/home-assistant.nix hosts/nuc/default.nix
git commit -m "feat: add Home Assistant module with Caddy proxy trust"
```

---

### Task 5: Cloudflare Tunnel Module

**Files:**
- Create: `modules/cloudflared.nix`
- Modify: `hosts/nuc/default.nix` (add import)

No standalone VM test — Cloudflare Tunnel needs external network access. Tested in integration test (service starts).

- [ ] **Step 1: Write the Cloudflare Tunnel module**

```nix
# modules/cloudflared.nix
{ config, lib, ... }:
{
  options.homelab.domain = lib.mkOption {
    type = lib.types.str;
    default = "example.com";
    description = "Your domain managed by Cloudflare.";
  };

  config = {
    services.cloudflared = {
      enable = true;
      tunnels.homelab = {
        # Credentials file created during setup via `cloudflared tunnel create`
        credentialsFile = "/etc/nixos/secrets/cloudflared-tunnel.json";
        ingress = {
          "adguard.${config.homelab.domain}" = "http://localhost:3000";
          "hass.${config.homelab.domain}" = "http://localhost:8123";
        };
        default = "http_status:404";
      };
    };
  };
}
```

- [ ] **Step 2: Add import to host config**

Add to `hosts/nuc/default.nix` imports:

```nix
    ../../modules/cloudflared.nix
```

And in the CUSTOMIZE section, add:

```nix
  # Your Cloudflare-managed domain
  homelab.domain = "example.com";
```

- [ ] **Step 3: Verify and commit**

Run: `nix flake show`

```bash
git add modules/cloudflared.nix hosts/nuc/default.nix
git commit -m "feat: add Cloudflare Tunnel module for remote access"
```

---

### Task 6: Integration Test

**Files:**
- Create: `tests/integration-test.nix`
- Modify: `flake.nix` (add check)

Boots a VM with all modules and verifies every service starts and responds.

- [ ] **Step 1: Write the integration test**

```nix
# tests/integration-test.nix
{ pkgs, ... }:
{
  name = "integration";

  nodes.machine = { pkgs, lib, ... }: {
    imports = [
      ../modules/common.nix
      ../modules/adguard.nix
      ../modules/caddy.nix
      ../modules/home-assistant.nix
      ../modules/cloudflared.nix
    ];

    # Override cloudflared credentials (no real tunnel in test)
    services.cloudflared.tunnels.homelab.credentialsFile = lib.mkForce (pkgs.writeText "dummy-creds" "{}");

    # Provide a dummy SSH key so common.nix evaluates
    homelab.sshKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest test@test" ];

    # Fake DNS for Caddy virtual hosts
    networking.hosts."127.0.0.1" = [ "adguard.home.lan" "hass.home.lan" ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # AdGuard Home
    machine.wait_for_unit("adguardhome.service")
    machine.wait_for_open_port(3000)
    machine.succeed("curl -sf http://localhost:3000")
    machine.succeed("${pkgs.dnsutils}/bin/dig @127.0.0.1 example.com +short +timeout=5")

    # Caddy
    machine.wait_for_unit("caddy.service")
    machine.wait_for_open_port(80)

    # Caddy proxies to AdGuard UI
    output = machine.succeed("curl -sf -H 'Host: adguard.home.lan' http://127.0.0.1")
    assert "AdGuard" in output or len(output) > 0, f"Caddy proxy to AdGuard failed: {output}"

    # Home Assistant (may take a while to start)
    machine.wait_for_unit("home-assistant.service", timeout=180)
    machine.wait_for_open_port(8123, timeout=180)
    machine.succeed("curl -sf http://localhost:8123 || curl -sf -o /dev/null -w '%{http_code}' http://localhost:8123 | grep -E '(200|401)'")

    # Cloudflare Tunnel service started (won't connect without real credentials)
    machine.wait_for_unit("cloudflared-tunnel-homelab.service")
  '';
}
```

- [ ] **Step 2: Wire into flake.nix**

Add to `flake.nix` checks:

```nix
      integration = linuxPkgs.nixosTest (import ./tests/integration-test.nix);
```

- [ ] **Step 3: Verify and commit**

Run: `nix flake show`

```bash
git add tests/integration-test.nix flake.nix
git commit -m "feat: add integration VM test for full service stack"
```

---

### Task 7: Colmena Deployment + deploy.sh

**Files:**
- Create: `deploy.sh`

The Colmena config is already in `flake.nix` from Task 1. This task adds the convenience wrapper script.

- [ ] **Step 1: Create `deploy.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-nuc}"

echo "Deploying to ${HOST}..."
echo "This will build on the target and activate the new configuration."
echo ""

colmena apply --on "${HOST}" --verbose

echo ""
echo "Deployment complete. If something is broken, SSH into the NUC and run:"
echo "  sudo nixos-rebuild switch --rollback"
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x deploy.sh
git add deploy.sh
git commit -m "feat: add deploy.sh wrapper for Colmena deployment"
```

---

### Task 8: Setup Script

**Files:**
- Create: `scripts/setup.sh`

This script runs from the NixOS live USB environment. It partitions the disk, sets up secrets, and installs NixOS from the flake.

- [ ] **Step 1: Create `scripts/setup.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "========================================"
echo "  NixOS Homelab Setup"
echo "========================================"
echo ""

# Check we're running as root (required for partitioning/installing)
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root."
  echo "  sudo bash scripts/setup.sh"
  exit 1
fi

# Detect disk
echo "Available disks:"
lsblk -d -o NAME,SIZE,TYPE | grep disk
echo ""
read -rp "Target disk (e.g., sda or nvme0n1): " DISK_NAME
TARGET_DISK="/dev/${DISK_NAME}"

if [[ ! -b "${TARGET_DISK}" ]]; then
  echo "Error: ${TARGET_DISK} is not a valid block device."
  exit 1
fi

echo ""
echo "WARNING: This will ERASE ALL DATA on ${TARGET_DISK}."
read -rp "Type 'yes' to continue: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

# Update disk device in disk.nix if needed
CURRENT_DEVICE=$(grep 'device =' "${REPO_DIR}/hosts/nuc/disk.nix" | head -1 | sed 's/.*"\(.*\)".*/\1/')
if [[ "${TARGET_DISK}" != "${CURRENT_DEVICE}" ]]; then
  echo "Updating disk.nix to use ${TARGET_DISK}..."
  sed -i "s|device = lib.mkDefault \".*\"|device = lib.mkDefault \"${TARGET_DISK}\"|" "${REPO_DIR}/hosts/nuc/disk.nix"
fi

# Partition and format with disko
echo ""
echo "Partitioning ${TARGET_DISK}..."
nix run github:nix-community/disko -- --mode disko "${REPO_DIR}/hosts/nuc/disk.nix"

echo "Disk partitioned and mounted at /mnt."

# Generate hardware config
echo ""
echo "Generating hardware configuration..."
nixos-generate-config --root /mnt --show-hardware-config > "${REPO_DIR}/hosts/nuc/hardware.nix"
echo "Hardware config written to hosts/nuc/hardware.nix"

# Secrets setup
echo ""
echo "========================================"
echo "  Secrets Setup"
echo "========================================"
mkdir -p /mnt/etc/nixos/secrets

echo ""
echo "Cloudflare Tunnel credentials JSON."
echo "Create a tunnel first: cloudflared tunnel create homelab"
echo "Then copy the credentials file path shown in the output."
echo "Leave blank to skip (you can set it up manually after boot)."
read -rp "Path to credentials JSON (e.g., ~/.cloudflared/<uuid>.json): " CF_CREDS
if [[ -n "${CF_CREDS}" && -f "${CF_CREDS}" ]]; then
  cp "${CF_CREDS}" /mnt/etc/nixos/secrets/cloudflared-tunnel.json
  chmod 600 /mnt/etc/nixos/secrets/cloudflared-tunnel.json
  echo "Saved."
else
  echo "Skipped. Set up Cloudflare Tunnel manually after boot."
fi

# Copy repo to target for the flake reference
echo ""
echo "Copying configuration to /mnt/etc/nixos/homelab..."
mkdir -p /mnt/etc/nixos
cp -r "${REPO_DIR}" /mnt/etc/nixos/homelab

# Install NixOS
echo ""
echo "Installing NixOS (this may take a while)..."
nixos-install --flake "/mnt/etc/nixos/homelab#nuc" --no-root-passwd

echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Remove the USB drive"
echo "  2. Reboot: reboot"
echo "  3. After boot, access AdGuard Home at http://192.168.1.50:3000"
echo "     (Run the setup wizard to set your admin password)"
echo "  4. Access Home Assistant at http://192.168.1.50:8123"
echo "     (Run the setup wizard to create your account)"
echo "  5. Point your router's DNS to the NUC's IP (192.168.1.50)"
echo "  6. Set up Colmena on your laptop for future deployments (see README)"
echo ""
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x scripts/setup.sh
git add scripts/setup.sh
git commit -m "feat: add setup script for bootstrapping NUC from live USB"
```

---

### Task 9: GitHub Actions CI

**Files:**
- Create: `.github/workflows/check.yml`

Runs `nix flake check` (which includes VM tests) on every push and PR. Uses Cachix for build caching.

- [ ] **Step 1: Create the workflow**

```yaml
# .github/workflows/check.yml
name: NixOS Check

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: cachix/install-nix-action@v27
        with:
          nix_path: nixpkgs=channel:nixos-24.11
          extra_nix_config: |
            experimental-features = nix-command flakes

      - uses: cachix/cachix-action@v15
        with:
          name: homelab
          authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
        continue-on-error: true  # CI works without Cachix, just slower

      - name: Check flake evaluates
        run: nix flake check --print-build-logs

      - name: Run AdGuard test
        run: nix build .#checks.x86_64-linux.adguard --print-build-logs

      - name: Run Caddy test
        run: nix build .#checks.x86_64-linux.caddy --print-build-logs

      - name: Run integration test
        run: nix build .#checks.x86_64-linux.integration --print-build-logs
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/check.yml
git commit -m "feat: add GitHub Actions CI with flake check and VM tests"
```

---

### Task 10: README

**Files:**
- Modify: `README.md`

Complete guide from bare NUC to running homelab. This is the primary documentation.

- [ ] **Step 1: Write the README**

```markdown
# Homelab

Declarative NixOS homelab running on an Intel NUC. Everything is defined in code — fork this repo, customize, and deploy.

## What You Get

| Service | What It Does | Access |
|---|---|---|
| **AdGuard Home** | Blocks ads and malware at the DNS level | `http://adguard.home.lan` |
| **Home Assistant** | Home automation hub | `http://hass.home.lan` |
| **Caddy** | Reverse proxy — gives services friendly URLs | Automatic |
| **Tailscale** | VPN — access your homelab from anywhere | Automatic |

## Prerequisites

- Intel NUC (or any x86_64 machine) with 8GB+ RAM
- USB drive (2GB+) for the NixOS installer
- A router where you can change the DNS server setting
- A computer to flash the USB and SSH from

## Quick Start

### 1. Fork and Customize

Fork this repo and edit `hosts/nuc/default.nix`:

```nix
# Set your NUC's static IP
networking.interfaces.eno1.ipv4.addresses = [{
  address = "192.168.1.50";  # ← your IP
  prefixLength = 24;
}];
networking.defaultGateway = "192.168.1.1";  # ← your router

# Set your timezone
time.timeZone = "America/New_York";  # ← your timezone

# Add your SSH public key
homelab.sshKeys = [
  "ssh-ed25519 AAAA... you@laptop"  # ← your key
];
```

If your NUC uses an NVMe drive instead of SATA, also update `hosts/nuc/disk.nix`:

```nix
device = lib.mkDefault "/dev/nvme0n1";  # default is /dev/sda
```

### 2. Flash NixOS

Download the [NixOS minimal ISO](https://nixos.org/download#nixos-iso) and flash it to a USB drive:

```bash
# macOS
sudo dd if=nixos-minimal-*.iso of=/dev/diskN bs=4M status=progress

# Linux
sudo dd if=nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress
```

### 3. Boot and Install

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
- Optionally set up Tailscale auth
- Install NixOS

7. Remove the USB drive and reboot

### 4. Post-Boot Setup

After the NUC reboots:

1. **AdGuard Home**: Visit `http://<nuc-ip>:3000` and complete the setup wizard (set admin password, configure filters)
2. **Home Assistant**: Visit `http://<nuc-ip>:8123` and create your account
3. **Router DNS**: Set your router's DNS server to the NUC's IP. All devices on your network now get ad blocking.
4. **Tailscale** (if you skipped during setup): SSH into the NUC and run `sudo tailscale up`

### 5. Set Up Nice URLs (Optional)

Once AdGuard Home is running, add DNS rewrites so you can use `adguard.home.lan` instead of IP addresses:

1. Open AdGuard Home at `http://<nuc-ip>:3000`
2. Go to **Filters → DNS rewrites**
3. Add a rewrite: `*.home.lan` → `<nuc-ip>` (e.g., `192.168.1.50`)

Now you can access:
- `http://adguard.home.lan` → AdGuard Home
- `http://hass.home.lan` → Home Assistant

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

Or pick a specific previous generation:

```bash
sudo nixos-rebuild switch --list-generations
sudo nixos-rebuild switch --generation <number>
```

### Adding Services

1. Create a new module: `modules/myservice.nix`
2. Import it in `hosts/nuc/default.nix`
3. Add a Caddy virtual host in `modules/caddy.nix`
4. Deploy: `./deploy.sh`

## Testing

Tests run as NixOS VMs — they boot a real (virtual) NixOS system and verify services work.

```bash
# Run on a Linux machine or in CI:
nix flake check                                         # all checks
nix build .#checks.x86_64-linux.adguard --print-build-logs   # single test
nix build .#checks.x86_64-linux.integration --print-build-logs  # full stack
```

CI runs all tests automatically on every push and PR.

## Secrets

This repo contains **zero secrets**. Sensitive data lives only on the NUC:

| Secret | Location on NUC | How It Gets There |
|---|---|---|
| Tailscale auth key | `/etc/nixos/secrets/tailscale-auth-key` | Setup script or manual |
| AdGuard admin password | AdGuard Home's own database | Setup wizard on first boot |
| Home Assistant account | Home Assistant's own database | Setup wizard on first boot |

## Repository Structure

```
flake.nix              # Entry point — inputs, host config, deployment, tests
hosts/nuc/
  default.nix          # NUC config — customize this for your setup
  hardware.nix         # Hardware-specific (generated during setup)
  disk.nix             # Disk partitioning layout
modules/
  common.nix           # Base system: SSH, users, firewall, packages
  adguard.nix          # AdGuard Home DNS blocking
  caddy.nix            # Caddy reverse proxy
  home-assistant.nix   # Home Assistant automation
  tailscale.nix        # Tailscale VPN
tests/
  adguard-test.nix     # VM test: DNS + web UI
  caddy-test.nix       # VM test: proxy routing
  integration-test.nix # VM test: all services together
scripts/
  setup.sh             # Bootstrap from NixOS live USB
deploy.sh              # Deploy changes from laptop
```

## License

MIT
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add comprehensive README with setup guide"
```

---

## Final Checklist

After all tasks are complete:

- [ ] `nix flake show` succeeds
- [ ] All files in the file map exist
- [ ] CI workflow exists and references all three tests
- [ ] README covers: fork → customize → flash → install → post-boot → day-to-day → testing
- [ ] No secrets in the repo (grep for private keys, passwords, auth tokens)
- [ ] `deploy.sh` and `scripts/setup.sh` are executable
