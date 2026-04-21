# Minecraft Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Bedrock-compatible Minecraft server (Java + GeyserMC + playit.gg) to the NixOS homelab.

**Architecture:** Java Minecraft server (NixOS module) on localhost:25565, GeyserMC standalone proxy translating Bedrock UDP:19132 to Java TCP:25565, and playit.gg agent tunneling UDP:19132 to the internet for remote Switch access.

**Tech Stack:** NixOS `services.minecraft-server`, GeyserMC standalone JAR, playit.gg Linux agent, systemd services.

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `modules/minecraft.nix` | Create | Java server + GeyserMC + playit.gg agent (all three services) |
| `hosts/nuc/default.nix` | Modify | Add import for minecraft module |
| `modules/adguard.nix` | Modify | Add `minecraft.home.lan` DNS rewrite |
| `modules/homepage.nix` | Modify | Add Minecraft dashboard card |
| `modules/backup.nix` | Modify | Add `/var/lib/minecraft` and `/var/lib/geyser` to backup paths |
| `tests/minecraft-test.nix` | Create | NixOS VM test for Minecraft + GeyserMC startup |
| `flake.nix` | Modify | Register minecraft test in checks |

---

### Task 1: Create Minecraft module with Java server

**Files:**
- Create: `modules/minecraft.nix`
- Modify: `hosts/nuc/default.nix`

- [ ] **Step 1: Create `modules/minecraft.nix` with Java server config**

```nix
{ config, lib, pkgs, ... }:
let
  # GeyserMC standalone — translates Bedrock (Switch) protocol to Java
  geyserVersion = "2.6.1";
  geyserBuild = "750";
  geyserJar = pkgs.fetchurl {
    url = "https://download.geysermc.org/v2/projects/geyser/versions/${geyserVersion}/builds/${geyserBuild}/downloads/standalone";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  geyserConfig = pkgs.writeText "geyser-config.yml" ''
    bedrock:
      address: 0.0.0.0
      port: 19132
      motd1: "Homelab Minecraft"
      motd2: ""
    remote:
      address: 127.0.0.1
      port: 25565
      auth-type: offline
    command-suggestions: true
    passthrough-motd: true
    passthrough-player-counts: true
    above-bedrock-nether-building: true
  '';

  # playit.gg agent — tunnels UDP for remote Bedrock access
  playitVersion = "0.15.26";
  playitBin = pkgs.stdenv.mkDerivation {
    pname = "playit";
    version = playitVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/playit-cloud/playit-agent/releases/download/v${playitVersion}/playit-linux-amd64";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/playit
      chmod +x $out/bin/playit
    '';
  };
in
{
  # ── Java Minecraft Server (NixOS built-in module) ──────────────
  services.minecraft-server = {
    enable = true;
    eula = true;
    package = pkgs.minecraft-server;

    jvmOpts = "-Xms4G -Xmx4G";

    serverProperties = {
      server-port = 25565;
      # Bind to localhost only — GeyserMC and direct LAN Java clients connect here
      server-ip = "127.0.0.1";
      motd = "Homelab Minecraft";
      max-players = 10;
      gamemode = "survival";
      difficulty = "normal";
      # Must be false for GeyserMC to proxy Bedrock players
      # Security is handled by the whitelist
      online-mode = false;
      white-list = true;
      enforce-whitelist = true;
    };

    # Whitelist — add players here as "name" = "offline-uuid"
    # For Bedrock players via GeyserMC, the name is prefixed with "."
    # Generate offline UUID: https://minecraft-serverlist.com/tools/offline-uuid
    whitelist = {
      # Example: ".SwitchPlayerName" = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx";
    };
  };

  # ── GeyserMC Standalone (Bedrock → Java proxy) ────────────────
  systemd.tmpfiles.rules = [
    "d /var/lib/geyser 0750 geyser geyser -"
  ];

  users.users.geyser = {
    isSystemUser = true;
    group = "geyser";
    home = "/var/lib/geyser";
  };
  users.groups.geyser = {};

  systemd.services.geyser = {
    description = "GeyserMC Bedrock-to-Java Proxy";
    wantedBy = [ "multi-user.target" ];
    after = [ "minecraft-server.service" ];
    requires = [ "minecraft-server.service" ];

    serviceConfig = {
      Type = "simple";
      User = "geyser";
      Group = "geyser";
      WorkingDirectory = "/var/lib/geyser";
      ExecStartPre = "${pkgs.coreutils}/bin/cp --no-preserve=mode ${geyserConfig} /var/lib/geyser/config.yml";
      ExecStart = "${pkgs.jre_headless}/bin/java -Xms256m -Xmx256m -jar ${geyserJar}";
      Restart = "always";
      RestartSec = 15;
    };
  };

  # ── playit.gg Agent (UDP tunnel for remote access) ────────────
  # Secret created during setup: sign up at playit.gg, create UDP tunnel,
  # save token to /etc/nixos/secrets/playit-secret.toml
  systemd.services.playit = {
    description = "playit.gg Tunnel Agent";
    wantedBy = [ "multi-user.target" ];
    after = [ "geyser.service" "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${playitBin}/bin/playit --secret_path /etc/nixos/secrets/playit-secret.toml";
      Restart = "always";
      RestartSec = 15;
      DynamicUser = true;
    };
  };

  # ── Firewall ──────────────────────────────────────────────────
  # UDP 19132 for LAN Bedrock play (playit.gg handles remote via outbound tunnel)
  networking.firewall.allowedUDPPorts = [ 19132 ];
}
```

Note on hashes and versions: The `fetchurl` hashes are placeholders. On first build, Nix will report the correct hash. Replace the `sha256-AAA...` values with the real hashes from the build error output. Also verify the latest stable versions before building:
- GeyserMC: check https://geysermc.org/download (standalone)
- playit.gg: check https://github.com/playit-cloud/playit-agent/releases

- [ ] **Step 2: Import the module in `hosts/nuc/default.nix`**

Add `../../modules/minecraft.nix` to the imports list in `hosts/nuc/default.nix`, after the backup import:

```nix
    ../../modules/backup.nix
    ../../modules/minecraft.nix
```

- [ ] **Step 3: Build to verify syntax and get real hashes**

Run: `nix build .#nixosConfigurations.nuc.config.system.build.toplevel --dry-run 2>&1 | head -40`

If hash mismatches are reported, copy the `got: sha256-...` values and update the two `hash` fields in `modules/minecraft.nix`.

Repeat the build until it evaluates cleanly (dry-run succeeds without hash errors).

- [ ] **Step 4: Commit**

```bash
git add modules/minecraft.nix hosts/nuc/default.nix
git commit -m "feat: add Minecraft server module with GeyserMC and playit.gg

Java server (NixOS module) + GeyserMC standalone proxy for Bedrock/Switch
support + playit.gg agent for remote access. Whitelist enabled."
```

---

### Task 2: Integrate with homepage, AdGuard DNS, and backups

**Files:**
- Modify: `modules/adguard.nix:37-45`
- Modify: `modules/homepage.nix:18-36`
- Modify: `modules/backup.nix:17-23`

- [ ] **Step 1: Add DNS rewrite to `modules/adguard.nix`**

Add this entry to the `filtering.rewrites` list, after the norish rewrite (line 43):

```nix
          { domain = "norish.${domain}"; answer = nucIp; }
          { domain = "minecraft.${domain}"; answer = nucIp; }
```

- [ ] **Step 2: Add Minecraft card to `modules/homepage.nix`**

Add a new "Gaming" service group after the existing "Services" group (after line 36):

```nix
      {
        "Gaming" = [
          {
            "Minecraft" = {
              icon = "minecraft";
              description = "Bedrock-compatible Minecraft server";
            };
          }
        ];
      }
```

- [ ] **Step 3: Add Minecraft paths to `modules/backup.nix`**

Add these paths to the `paths` list in `services.restic.backups.usb` (after line 22):

```nix
      "/var/lib/minecraft"
      "/var/lib/geyser"
```

- [ ] **Step 4: Verify the config still evaluates**

Run: `nix eval .#nixosConfigurations.nuc.config.system.build.toplevel --raw 2>&1 | tail -5`

Expected: No errors (outputs a nix store path).

- [ ] **Step 5: Commit**

```bash
git add modules/adguard.nix modules/homepage.nix modules/backup.nix
git commit -m "feat: integrate Minecraft with homepage, DNS, and backups"
```

---

### Task 3: Add NixOS VM test

**Files:**
- Create: `tests/minecraft-test.nix`
- Modify: `flake.nix:51-54`
- Modify: `tests/integration-test.nix`

- [ ] **Step 1: Create `tests/minecraft-test.nix`**

```nix
{ pkgs, ... }:
{
  name = "minecraft";

  nodes.machine = { pkgs, lib, ... }: {
    imports = [
      ../modules/common.nix
      ../modules/minecraft.nix
    ];

    homelab.sshKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest test@test" ];

    # Disable playit.gg in test — needs internet access to connect to playit servers
    systemd.services.playit.enable = lib.mkForce false;

    # Give the VM enough memory for the Minecraft server
    virtualisation.memorySize = 4096;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Java Minecraft server starts and listens
    machine.wait_for_unit("minecraft-server.service", timeout=180)
    machine.wait_for_open_port(25565, timeout=180)

    # GeyserMC starts and listens on Bedrock port
    machine.wait_for_unit("geyser.service", timeout=120)
    machine.wait_for_open_port(19132, timeout=120)
  '';
}
```

- [ ] **Step 2: Register the test in `flake.nix`**

Add the minecraft test to the `checks` attrset (after line 53):

```nix
      caddy = linuxPkgs.nixosTest (import ./tests/caddy-test.nix);
      minecraft = linuxPkgs.nixosTest (import ./tests/minecraft-test.nix);
      integration = linuxPkgs.nixosTest (import ./tests/integration-test.nix);
```

- [ ] **Step 3: Add Minecraft to the integration test**

In `tests/integration-test.nix`, add the import (after line 14):

```nix
      ../modules/crowdsec.nix
      ../modules/minecraft.nix
    ];
```

Disable playit.gg in the test overrides (after line 34):

```nix
    systemd.services.playit.enable = lib.mkForce false;
```

Add memory for the Minecraft server (after the networking.hosts line):

```nix
    virtualisation.memorySize = 4096;
```

Add Minecraft checks to the test script (before the closing `''`):

```python
    # Minecraft Java server
    machine.wait_for_unit("minecraft-server.service", timeout=180)
    machine.wait_for_open_port(25565, timeout=180)
```

- [ ] **Step 4: Run the standalone Minecraft test**

Run: `nix build .#checks.x86_64-linux.minecraft --print-build-logs 2>&1 | tail -30`

Expected: Test passes — both `minecraft-server.service` and `geyser.service` start, ports 25565 and 19132 open.

If `wait_for_open_port` times out for GeyserMC (port 19132), it may be because GeyserMC takes longer to start. Increase the timeout or check if GeyserMC needs the Minecraft server to be fully ready (world loaded) before it connects.

- [ ] **Step 5: Commit**

```bash
git add tests/minecraft-test.nix flake.nix tests/integration-test.nix
git commit -m "test: add NixOS VM test for Minecraft server and GeyserMC"
```

---

### Task 4: Fix hashes and verify full build

This task handles the hash resolution that couldn't be done in Task 1 without actually running the build.

- [ ] **Step 1: Attempt a full build to get real hashes**

Run: `nix build .#nixosConfigurations.nuc.config.system.build.toplevel 2>&1 | grep "got:" | head -5`

Expected: Hash mismatch errors with `got: sha256-...` lines. Copy each real hash.

- [ ] **Step 2: Update GeyserMC hash in `modules/minecraft.nix`**

Replace the GeyserMC `hash = "sha256-AAA..."` placeholder with the real hash from the build output.

- [ ] **Step 3: Update playit.gg hash in `modules/minecraft.nix`**

Replace the playit.gg `hash = "sha256-AAA..."` placeholder with the real hash from the build output.

- [ ] **Step 4: Verify the build evaluates cleanly**

Run: `nix build .#nixosConfigurations.nuc.config.system.build.toplevel --dry-run`

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add modules/minecraft.nix
git commit -m "fix: update GeyserMC and playit.gg hashes"
```

---

### Task 5: Verify and finalize

- [ ] **Step 1: Run all checks**

Run: `nix flake check 2>&1 | tail -20`

Expected: All checks pass (adguard, caddy, minecraft, integration).

- [ ] **Step 2: Verify no formatting issues**

Run: `nix develop --command nixpkgs-fmt --check modules/minecraft.nix`

If formatting issues are reported, fix with: `nix develop --command nixpkgs-fmt modules/minecraft.nix`

- [ ] **Step 3: Commit any formatting fixes**

```bash
git add modules/minecraft.nix
git commit -m "style: format minecraft module"
```

---

## Post-Deploy Setup (Manual, One-Time)

These steps happen after deploying to the NUC with `./deploy.sh`:

1. **playit.gg setup:**
   - Sign up at [playit.gg](https://playit.gg)
   - Download and run the agent once locally to claim it: `ssh nuc 'sudo playit setup'`
   - Or: create a tunnel in the web dashboard, copy the secret
   - Save to: `ssh nuc 'sudo tee /etc/nixos/secrets/playit-secret.toml'`
   - Restart: `ssh nuc 'sudo systemctl restart playit'`

2. **Add players to whitelist:**
   - Edit `modules/minecraft.nix`, add entries to `whitelist = { ... }`
   - For Bedrock players via GeyserMC, prefix the name with `.` (e.g., `.SwitchPlayerName`)
   - Get the offline UUID from: https://minecraft-serverlist.com/tools/offline-uuid
   - Redeploy: `./deploy.sh`

3. **On Nintendo Switch:**
   - Open Minecraft → Servers → Add Server
   - Enter the playit.gg public address and port
   - For LAN play: use `192.168.178.83` port `19132`
