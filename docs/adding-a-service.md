# Adding a New Service to the Homelab

Step-by-step guide for adding a new service. Use this as a checklist — not every service needs every step (e.g., a local-only service skips Cloudflare Tunnel).

## 1. Create the service module

Create `modules/<service>.nix`. Two patterns depending on the service type:

### Native NixOS service

For services with NixOS module support (e.g., Home Assistant, AdGuard):

```nix
{ config, lib, pkgs, ... }:
{
  services.<service> = {
    enable = true;
    # service-specific config
  };

  networking.firewall.allowedTCPPorts = [ <port> ];
}
```

### OCI container service

For services distributed as Docker images, use Podman OCI containers:

```nix
{ config, lib, pkgs, ... }:
{
  # Enable Podman
  virtualisation.podman.enable = true;

  # Create a dedicated network if multiple containers need to communicate
  systemd.services."podman-<service>-network" = {
    description = "Create podman network for <service>";
    after = [ "podman.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.podman}/bin/podman network create <service> --ignore";
    };
  };

  # Create persistent data directories
  systemd.tmpfiles.rules = [
    "d /var/lib/<service>/data 0755 root root -"
  ];

  # Define containers
  virtualisation.oci-containers = {
    backend = "podman";
    containers.<service> = {
      image = "<image>:<tag>";
      ports = [ "<host-port>:<container-port>" ];
      environment = { /* ... */ };
      environmentFiles = [ "/etc/nixos/secrets/<service>-env" ]; # for secrets
      volumes = [ "/var/lib/<service>/data:/app/data" ];
      extraOptions = [ "--network=<service>" ];
      dependsOn = [ "<service>-db" ]; # if applicable
    };
  };

  networking.firewall.allowedTCPPorts = [ <host-port> ];
}
```

Key points:
- Use `environmentFiles` to load secrets — never put secrets in Nix config (they end up in the world-readable Nix store).
- Use bind mounts under `/var/lib/<service>/` for persistent data.
- Only expose the main app port to the host; supporting services (DB, Redis, etc.) stay on the internal Podman network.
- Add `dependsOn` so the app container waits for its dependencies.

## 2. Import in host config

Edit `hosts/nuc/default.nix`:

```nix
imports = [
  # ... existing imports
  ../../modules/<service>.nix
];
```

## 3. Add Caddy reverse proxy

Edit `modules/caddy.nix` — add a virtual host for the `.home.lan` address:

```nix
virtualHosts."http://<service>.home.lan".extraConfig = ''
  reverse_proxy localhost:<host-port>
'';
```

This allows access via `http://<service>.home.lan` on the local network (resolved by AdGuard's `*.home.lan` wildcard).

## 4. Add Cloudflare Tunnel ingress (for external access)

Edit `modules/cloudflared.nix` — add an ingress rule:

```nix
ingress = {
  # ... existing rules
  "<service>.${config.homelab.domain}" = "http://localhost:<host-port>";
};
```

Then add a DNS rewrite in `modules/adguard.nix` so LAN clients bypass the tunnel:

```nix
{ domain = "<service>.${domain}"; answer = nucIp; }
```

After deploying, create the DNS record in Cloudflare:
- Type: CNAME
- Name: `<service>`
- Target: the tunnel UUID (same as other services)

## 5. Add to Homepage dashboard

Edit `modules/homepage.nix` — add a service card:

```nix
{
  "<Service Name>" = {
    icon = "<icon-name>"; # see https://gethomepage.dev/configs/services/#icons
    href = "https://<service>.${domain}";
    description = "<one-line description>";
  };
}
```

## 6. Add to backups

Edit `modules/backup.nix` — add the data directory to `paths`:

```nix
paths = [
  # ... existing paths
  "/var/lib/<service>"
];
```

## 7. Handle secrets

If the service needs secrets (API keys, master keys, etc.):

1. **Generate on setup**: Add to `scripts/setup-apps.sh`
2. **Store in 1Password**: Add to `scripts/secrets-to-op.sh`
3. **Restore from 1Password**: Add to `scripts/secrets-from-op.sh`

Secrets live in `/etc/nixos/secrets/` on the NUC (already backed up by restic).

For OCI containers, write secrets as env files:
```bash
echo "SECRET_KEY=<value>" | ssh nuc "sudo tee /etc/nixos/secrets/<service>-env > /dev/null"
```

Then reference via `environmentFiles` in the container config.

## 8. Deploy

```bash
nix develop
./deploy.sh
```

## 9. Post-deploy

- Run `scripts/setup-apps.sh` if the service needs initial account setup
- Verify the service is running: `ssh nuc 'systemctl status podman-<service>'`
- Check logs: `ssh nuc 'journalctl -u podman-<service> -f'`
- Test access: open `https://<service>.danielmschmidt.de` or `http://<service>.home.lan`

## Quick Reference: Port Allocation

| Port | Service |
|------|---------|
| 53 | AdGuard DNS |
| 80, 443 | Caddy |
| 3000 | AdGuard Web UI |
| 8082 | Homepage |
| 8083 | Norish |
| 8123 | Home Assistant |

Pick the next available port for new services.
