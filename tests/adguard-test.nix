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

    # DNS service responds (VM has no internet, so upstream forwarding fails with SERVFAIL —
    # but getting any response proves AdGuard is listening and processing queries on port 53)
    machine.succeed("${pkgs.dnsutils}/bin/dig @127.0.0.1 example.com +timeout=5 +noall +comments | grep -q 'status:'")
  '';
}
