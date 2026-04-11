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

    # DNS resolves queries successfully (not just listening, actually forwarding)
    machine.succeed("${pkgs.dnsutils}/bin/dig @127.0.0.1 example.com +noall +comments +timeout=5 | grep -q 'NOERROR'")
  '';
}
