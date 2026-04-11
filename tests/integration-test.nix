# Function form so pkgs is in scope for testScript interpolation
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
    machine.succeed("${pkgs.dnsutils}/bin/dig @127.0.0.1 example.com +noall +comments +timeout=5 | grep -q 'NOERROR'")

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
