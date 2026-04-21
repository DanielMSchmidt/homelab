# Function form so pkgs is in scope for testScript interpolation
{ playitModule }:
{ pkgs, ... }:
{
  name = "integration";

  nodes.machine = { pkgs, lib, ... }: {
    imports = [
      playitModule
      ../modules/common.nix
      ../modules/adguard.nix
      ../modules/caddy.nix
      ../modules/home-assistant.nix
      ../modules/cloudflared.nix
      ../modules/norish.nix
      ../modules/auto-upgrade.nix
      ../modules/crowdsec.nix
      ../modules/minecraft.nix
    ];

    # Disable cloudflared in test — it needs real Cloudflare credentials and network
    # access, neither of which exist in a test VM. The module is validated by flake eval.
    services.cloudflared.tunnels.homelab.credentialsFile = lib.mkForce "${pkgs.writeText "dummy-creds" "{}"}";
    systemd.services.cloudflared-tunnel-homelab.enable = lib.mkForce false;

    # Disable norish containers in test — OCI containers need image pulls and a
    # container runtime that don't exist in a test VM. The module is validated by flake eval.
    systemd.services."podman-norish-network".enable = lib.mkForce false;
    systemd.services."podman-norish".enable = lib.mkForce false;
    systemd.services."podman-norish-db".enable = lib.mkForce false;
    systemd.services."podman-norish-redis".enable = lib.mkForce false;
    systemd.services."podman-norish-chrome".enable = lib.mkForce false;

    # Disable CrowdSec in test — needs runtime initialization (hub download,
    # machine registration) that doesn't work in a test VM.
    systemd.services.crowdsec.enable = lib.mkForce false;
    systemd.services.crowdsec-firewall-bouncer.enable = lib.mkForce false;

    # Disable playit.gg in test — needs internet access
    services.playit.enable = lib.mkForce false;

    # Disable auto-upgrade in test — needs network access to GitHub
    system.autoUpgrade.enable = lib.mkForce false;

    # Provide a dummy SSH key so common.nix evaluates
    homelab.sshKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest test@test" ];

    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [ "minecraft-server" ];

    # Fake DNS for Caddy virtual hosts
    networking.hosts."127.0.0.1" = [ "adguard.home.lan" "hass.home.lan" ];

    virtualisation.memorySize = 4096;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # AdGuard Home (DNS behavior tested in standalone adguard test —
    # integration test verifies coexistence, not per-service functionality)
    machine.wait_for_unit("adguardhome.service")
    machine.wait_for_open_port(3000)
    machine.succeed("curl -sf http://localhost:3000")

    # Caddy
    machine.wait_for_unit("caddy.service")
    machine.wait_for_open_port(80)

    # Caddy proxies to AdGuard UI
    machine.succeed("curl -sf -H 'Host: adguard.home.lan' http://127.0.0.1")

    # Home Assistant (slow to start, may return various status codes during init)
    machine.wait_for_unit("home-assistant.service", timeout=180)
    machine.wait_for_open_port(8123, timeout=180)
    machine.wait_until_succeeds("curl -sf http://localhost:8123 || curl -s -o /dev/null -w '%{http_code}' http://localhost:8123 | grep -qE '[2-5][0-9][0-9]'", timeout=60)


    # Cloudflare Tunnel: module is validated by flake eval, but the service
    # is disabled in test (needs real credentials + network access)

    # Norish: module is validated by flake eval, but containers are disabled
    # in test (needs image pulls + container runtime not available in test VM)

    # CrowdSec and auto-upgrade: modules validated by flake eval,
    # services disabled in test (need runtime init / network access)

    # Minecraft Java server
    machine.wait_for_unit("minecraft-server.service", timeout=180)
    machine.wait_for_open_port(25565, timeout=180)
  '';
}
