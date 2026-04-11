{ ... }:
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
