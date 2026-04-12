# CrowdSec + Auto-Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automatic nightly NixOS upgrades (via GitHub Action + system.autoUpgrade) and CrowdSec intrusion detection with firewall bouncing.

**Architecture:** GitHub Action updates flake.lock daily, NUC pulls and rebuilds at 4am. CrowdSec engine monitors SSH and Caddy logs, firewall bouncer bans attackers via nftables.

**Tech Stack:** NixOS, GitHub Actions, CrowdSec, nftables

**Spec:** `docs/superpowers/specs/2026-04-12-security-autoupgrade-design.md`

---

### Task 1: Create auto-upgrade module

**Files:**
- Create: `modules/auto-upgrade.nix`

- [ ] **Step 1: Create `modules/auto-upgrade.nix`**

```nix
{ config, lib, ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "github:DanielMSchmidt/homelab";
    dates = "04:00";
    allowReboot = true;
    rebootWindow = { lower = "04:00"; upper = "05:00"; };
  };
}
```

- [ ] **Step 2: Verify it parses**

Run: `nix-instantiate --parse modules/auto-upgrade.nix`
Expected: Nix AST output, no errors

- [ ] **Step 3: Commit**

```bash
git add modules/auto-upgrade.nix
git commit -m "feat: add auto-upgrade module"
```

---

### Task 2: Create GitHub Action for flake lock updates

**Files:**
- Create: `.github/workflows/update-flake.yml`

- [ ] **Step 1: Create `.github/workflows/update-flake.yml`**

```yaml
name: Update Flake Lock

on:
  schedule:
    - cron: '30 1 * * *'  # 1:30 UTC = 3:30 CEST (before 4am NUC upgrade)
  workflow_dispatch: {}     # allow manual trigger

jobs:
  update:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4

      - uses: cachix/install-nix-action@v27
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes

      - name: Update flake lock
        run: nix flake update

      - name: Commit and push if changed
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git diff --quiet flake.lock && echo "No changes" && exit 0
          git add flake.lock
          git commit -m "chore: update flake.lock"
          git push
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/update-flake.yml
git commit -m "feat: add github action for nightly flake lock updates"
```

---

### Task 3: Create CrowdSec module

**Files:**
- Create: `modules/crowdsec.nix`

This is the largest task — CrowdSec engine service, firewall bouncer service, config files, and initialization.

- [ ] **Step 1: Create `modules/crowdsec.nix`**

```nix
{ config, lib, pkgs, ... }:
let
  # CrowdSec config files written to the Nix store (read-only)
  configDir = "/etc/crowdsec";
  dataDir = "/var/lib/crowdsec";

  crowdsecConfig = pkgs.writeText "crowdsec-config.yaml" ''
    common:
      daemonize: false
      log_media: stdout
      log_level: info
    config_paths:
      config_dir: ${configDir}/
      data_dir: ${dataDir}/data/
      simulation_path: ${configDir}/simulation.yaml
      hub_dir: ${dataDir}/hub/
      index_path: ${dataDir}/hub/.index.json
      notification_dir: ${configDir}/notifications/
      plugin_dir: ${configDir}/plugins/
      pattern_dir: ${pkgs.crowdsec}/share/crowdsec/config/patterns
    crowdsec_service:
      acquisition_path: ${configDir}/acquis.yaml
      acquisition_dir: ${configDir}/acquis.d
      parser_routines: 1
    cscli:
      output: human
    db_config:
      type: sqlite
      db_path: ${dataDir}/data/crowdsec.db
      use_wal: true
    api:
      client:
        insecure_skip_verify: false
        credentials_path: ${dataDir}/credentials/local_api_credentials.yaml
      server:
        log_level: info
        listen_uri: 127.0.0.1:8080
        profiles_path: ${configDir}/profiles.yaml
        console_path: ${dataDir}/credentials/console.yaml
        online_client:
          credentials_path: ${dataDir}/credentials/online_api_credentials.yaml
        trusted_ips:
          - 127.0.0.1
          - ::1
    prometheus:
      enabled: true
      level: full
      listen_addr: 127.0.0.1
      listen_port: 6060
  '';

  acquis = pkgs.writeText "crowdsec-acquis.yaml" ''
    source: journalctl
    journalctl_filter:
      - "_SYSTEMD_UNIT=sshd.service"
    labels:
      type: syslog
    ---
    source: file
    filenames:
      - /var/log/caddy/*.log
    labels:
      type: caddy
  '';

  simulation = pkgs.writeText "crowdsec-simulation.yaml" ''
    simulation: false
  '';

  profiles = pkgs.writeText "crowdsec-profiles.yaml" ''
    name: default_ip_remediation
    filters:
      - Alert.Remediation == true && Alert.GetScope() == "Ip"
    decisions:
      - type: ban
        duration: 4h
    on_success: break
    ---
    name: default_range_remediation
    filters:
      - Alert.Remediation == true && Alert.GetScope() == "Range"
    decisions:
      - type: ban
        duration: 4h
    on_success: break
  '';

  # Bouncer config is NOT in the Nix store — it contains the API key secret.
  # Written to /etc/nixos/secrets/crowdsec-bouncer.yaml by setup-apps.sh.

  cscli = "${pkgs.crowdsec}/bin/cscli -c ${configDir}/config.yaml";
in
{
  # Config files in /etc/crowdsec (symlinked from Nix store)
  environment.etc = {
    "crowdsec/config.yaml".source = crowdsecConfig;
    "crowdsec/acquis.yaml".source = acquis;
    "crowdsec/simulation.yaml".source = simulation;
    "crowdsec/profiles.yaml".source = profiles;
  };

  # Persistent directories
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 crowdsec crowdsec -"
    "d ${dataDir}/data 0750 crowdsec crowdsec -"
    "d ${dataDir}/hub 0750 crowdsec crowdsec -"
    "d ${dataDir}/credentials 0750 crowdsec crowdsec -"
    "d ${configDir}/acquis.d 0755 root root -"
    "d ${configDir}/notifications 0755 root root -"
    "d ${configDir}/plugins 0755 root root -"
    "d /var/log/caddy 0755 caddy caddy -"
  ];

  # CrowdSec system user (needs systemd-journal group for journald access)
  users.users.crowdsec = {
    isSystemUser = true;
    group = "crowdsec";
    extraGroups = [ "systemd-journal" ];
    home = dataDir;
  };
  users.groups.crowdsec = {};

  # CrowdSec engine service
  systemd.services.crowdsec = {
    description = "CrowdSec Security Engine";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      Type = "notify";
      User = "crowdsec";
      Group = "crowdsec";
      ExecStartPre = let
        initScript = pkgs.writeShellScript "crowdsec-init" ''
          # Update hub index and install collections on first run
          if [ ! -f ${dataDir}/hub/.index.json ]; then
            ${cscli} hub update
            ${cscli} collections install crowdsecurity/linux
            ${cscli} collections install crowdsecurity/sshd
            ${cscli} collections install crowdsecurity/caddy
          fi

          # Register machine if not already registered
          if [ ! -f ${dataDir}/credentials/local_api_credentials.yaml ] || \
             ! grep -q "login:" ${dataDir}/credentials/local_api_credentials.yaml; then
            ${cscli} machines add nuc --auto --force
          fi

          # Register with CAPI (community blocklists) if not done
          if [ ! -f ${dataDir}/credentials/online_api_credentials.yaml ] || \
             ! grep -q "login:" ${dataDir}/credentials/online_api_credentials.yaml; then
            ${cscli} capi register || true
          fi
        '';
      in "+${initScript}";  # + prefix = run as root for first-time setup
      ExecStart = "${pkgs.crowdsec}/bin/crowdsec -c ${configDir}/config.yaml";
      Restart = "always";
      RestartSec = 60;
      ReadWritePaths = [ dataDir "/var/log/caddy" ];
      SupplementaryGroups = [ "systemd-journal" ];
    };
  };

  # Firewall bouncer service
  # The bouncer config with API key lives at /etc/nixos/secrets/crowdsec-bouncer.yaml
  # Generated during setup via: cscli bouncers add firewall-bouncer
  systemd.services.crowdsec-firewall-bouncer = {
    description = "CrowdSec Firewall Bouncer";
    wantedBy = [ "multi-user.target" ];
    after = [ "crowdsec.service" ];
    requires = [ "crowdsec.service" ];

    serviceConfig = {
      Type = "notify";
      ExecStart = "${pkgs.crowdsec-firewall-bouncer}/bin/cs-firewall-bouncer -c /etc/nixos/secrets/crowdsec-bouncer.yaml";
      Restart = "always";
      RestartSec = 10;
      AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
      CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
    };
  };

  environment.systemPackages = [ pkgs.crowdsec ];
}
```

- [ ] **Step 2: Verify it parses**

Run: `nix-instantiate --parse modules/crowdsec.nix`
Expected: Nix AST output, no errors

- [ ] **Step 3: Commit**

```bash
git add modules/crowdsec.nix
git commit -m "feat: add crowdsec module with engine and firewall bouncer"
```

---

### Task 4: Enable Caddy access logging

**Files:**
- Modify: `modules/caddy.nix`

CrowdSec needs Caddy access logs in a file it can read. Add a global log configuration.

- [ ] **Step 1: Add global access log to Caddy**

In `modules/caddy.nix`, add `globalConfig` to the `services.caddy` block:

```nix
    globalConfig = ''
      log {
        output file /var/log/caddy/access.log {
          roll_size 50MiB
          roll_keep 3
        }
        format json
      }
    '';
```

- [ ] **Step 2: Commit**

```bash
git add modules/caddy.nix
git commit -m "feat: enable caddy json access logging for crowdsec"
```

---

### Task 5: Wire modules into host config

**Files:**
- Modify: `hosts/nuc/default.nix`

- [ ] **Step 1: Add imports**

Add to the imports list in `hosts/nuc/default.nix`, before `../../modules/backup.nix`:

```nix
    ../../modules/auto-upgrade.nix
    ../../modules/crowdsec.nix
```

- [ ] **Step 2: Commit**

```bash
git add hosts/nuc/default.nix
git commit -m "feat: import auto-upgrade and crowdsec modules"
```

---

### Task 6: Add CrowdSec data to backups

**Files:**
- Modify: `modules/backup.nix`

- [ ] **Step 1: Add CrowdSec data to backup paths**

Add to the `paths` list in `modules/backup.nix`:

```nix
      "/var/lib/crowdsec"
```

- [ ] **Step 2: Commit**

```bash
git add modules/backup.nix
git commit -m "feat: add crowdsec data to restic backups"
```

---

### Task 7: Add CrowdSec setup to setup-apps.sh

**Files:**
- Modify: `scripts/setup-apps.sh`

The firewall bouncer needs an API key generated by `cscli`. This is a one-time setup step.

- [ ] **Step 1: Add CrowdSec section to setup-apps.sh**

Add after the Norish section and before the `# --- Store in 1Password ---` section:

```bash
# --- CrowdSec ---
echo "Setting up CrowdSec firewall bouncer..."

BOUNCER_CONFIG="/etc/nixos/secrets/crowdsec-bouncer.yaml"
BOUNCER_EXISTS=$(ssh "${TARGET}" "sudo test -f ${BOUNCER_CONFIG} && echo 'yes' || echo 'no'" | tail -1)

if [[ "${BOUNCER_EXISTS}" == "yes" ]] && ! $FORCE; then
  echo "  Bouncer config already exists. Skipping. (use --force to recreate)"
else
  # Wait for CrowdSec to be ready
  echo "  Waiting for CrowdSec engine..."
  for i in $(seq 1 30); do
    if ssh "${TARGET}" "sudo cscli -c /etc/crowdsec/config.yaml machines list" &>/dev/null; then
      break
    fi
    sleep 2
  done

  # Register bouncer and get API key
  BOUNCER_KEY=$(ssh "${TARGET}" "sudo cscli -c /etc/crowdsec/config.yaml bouncers add firewall-bouncer --output raw 2>/dev/null || \
    sudo cscli -c /etc/crowdsec/config.yaml bouncers delete firewall-bouncer 2>/dev/null && \
    sudo cscli -c /etc/crowdsec/config.yaml bouncers add firewall-bouncer --output raw")

  if [[ -n "${BOUNCER_KEY}" ]]; then
    # Write bouncer config with the API key
    ssh "${TARGET}" "sudo tee ${BOUNCER_CONFIG} > /dev/null" <<BOUNCER_EOF
mode: nftables
update_frequency: 10s
log_mode: stdout
log_level: info
api_url: http://127.0.0.1:8080/
api_key: ${BOUNCER_KEY}
disable_ipv6: false
deny_action: DROP
deny_log: false
nftables:
  ipv4:
    enabled: true
    set-only: false
    table: crowdsec
    chain: crowdsec-chain
    priority: -10
  ipv6:
    enabled: true
    set-only: false
    table: crowdsec6
    chain: crowdsec6-chain
    priority: -10
nftables_hooks:
  - input
  - forward
BOUNCER_EOF
    ssh "${TARGET}" "sudo chmod 600 ${BOUNCER_CONFIG}"
    echo "  ✓ CrowdSec bouncer registered and config written"

    # Restart the bouncer to pick up the config
    ssh "${TARGET}" "sudo systemctl restart crowdsec-firewall-bouncer" || true
  else
    echo "  Warning: Could not register CrowdSec bouncer. Set up manually."
  fi
fi
```

- [ ] **Step 2: Commit**

```bash
git add scripts/setup-apps.sh
git commit -m "feat: add crowdsec bouncer setup to setup-apps.sh"
```

---

### Task 8: Add CrowdSec secrets to 1Password scripts

**Files:**
- Modify: `scripts/secrets-to-op.sh`
- Modify: `scripts/secrets-from-op.sh`

- [ ] **Step 1: Add to secrets-to-op.sh**

Add after fetching norish env (after the norish line):

```bash
CROWDSEC_BOUNCER=$(ssh nuc 'sudo cat /etc/nixos/secrets/crowdsec-bouncer.yaml')
echo "  ✓ CrowdSec bouncer config"
```

Add to the `op item create` command as a new field:

```bash
  "crowdsec_bouncer[password]=${CROWDSEC_BOUNCER}" \
```

- [ ] **Step 2: Add to secrets-from-op.sh**

Add after fetching norish env:

```bash
CROWDSEC_BOUNCER=$(op item get "${ITEM_NAME}" --fields crowdsec_bouncer)
echo "  ✓ CrowdSec bouncer config"
```

Add after writing norish env:

```bash
echo "${CROWDSEC_BOUNCER}" | ssh "${TARGET}" "sudo tee /etc/nixos/secrets/crowdsec-bouncer.yaml > /dev/null"
ssh "${TARGET}" "sudo chmod 600 /etc/nixos/secrets/crowdsec-bouncer.yaml"
echo "  ✓ CrowdSec bouncer config"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/secrets-to-op.sh scripts/secrets-from-op.sh
git commit -m "feat: add crowdsec bouncer config to 1password backup/restore"
```

---

### Task 9: Update integration test

**Files:**
- Modify: `tests/integration-test.nix`

- [ ] **Step 1: Add imports and disable CrowdSec in test**

Add to the imports list in `tests/integration-test.nix`:

```nix
      ../modules/auto-upgrade.nix
      ../modules/crowdsec.nix
```

Add after the norish disable block:

```nix
    # Disable CrowdSec in test — needs runtime initialization (hub download,
    # machine registration) that doesn't work in a test VM.
    systemd.services.crowdsec.enable = lib.mkForce false;
    systemd.services.crowdsec-firewall-bouncer.enable = lib.mkForce false;

    # Disable auto-upgrade in test — needs network access to GitHub
    system.autoUpgrade.enable = lib.mkForce false;
```

Add a comment in the testScript before the closing `''`:

```python
    # CrowdSec and auto-upgrade: modules validated by flake eval,
    # services disabled in test (need runtime init / network access)
```

- [ ] **Step 2: Commit**

```bash
git add tests/integration-test.nix
git commit -m "feat: add crowdsec and auto-upgrade to integration test"
```

---

### Task 10: Validate with nix flake check

**Files:** none (validation only)

- [ ] **Step 1: Verify nix eval of the NUC config**

Run: `nix eval .#nixosConfigurations.nuc.config.system.autoUpgrade.enable --json`
Expected: `true`

- [ ] **Step 2: Verify CrowdSec services exist**

Run: `nix eval .#nixosConfigurations.nuc.config.systemd.services.crowdsec.serviceConfig.ExecStart --json`
Expected: JSON string containing `crowdsec -c /etc/crowdsec/config.yaml`

- [ ] **Step 3: Run nix flake check**

Run: `nix flake check --no-build 2>&1 | tail -10`
Expected: No errors. Warnings about incompatible systems are OK.

---

### Post-deploy checklist (not automated)

After running `./deploy.sh`:

1. Verify auto-upgrade timer: `ssh nuc 'systemctl status nixos-upgrade.timer'`
2. Verify CrowdSec is running: `ssh nuc 'sudo systemctl status crowdsec'`
3. Run `bash scripts/setup-apps.sh` to register the firewall bouncer
4. Verify bouncer is running: `ssh nuc 'sudo systemctl status crowdsec-firewall-bouncer'`
5. Check CrowdSec metrics: `ssh nuc 'sudo cscli -c /etc/crowdsec/config.yaml metrics'`
6. Check installed collections: `ssh nuc 'sudo cscli -c /etc/crowdsec/config.yaml collections list'`
7. Test detection: `ssh nuc 'sudo cscli -c /etc/crowdsec/config.yaml decisions list'`
