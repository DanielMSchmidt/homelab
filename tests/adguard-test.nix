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

    # DNS service responds (VM has no internet, so upstream forwarding returns SERVFAIL —
    # dig exits 0 if it gets any response, proving AdGuard is processing queries on port 53)
    machine.wait_for_open_port(53)
    machine.succeed("${pkgs.dnsutils}/bin/dig @127.0.0.1 example.com +timeout=5")
  '';
}
