{ ... }:
{
  services.caddy = {
    enable = true;

    globalConfig = ''
      log {
        output file /var/log/caddy/access.log {
          roll_size 50MiB
          roll_keep 3
        }
        format json
      }
    '';

    virtualHosts."http://adguard.home.lan".extraConfig = ''
      reverse_proxy localhost:3000
    '';

    virtualHosts."http://hass.home.lan".extraConfig = ''
      reverse_proxy localhost:8123
    '';

    virtualHosts."http://home.home.lan".extraConfig = ''
      reverse_proxy localhost:8082
    '';

    virtualHosts."http://norish.home.lan".extraConfig = ''
      reverse_proxy localhost:8083
    '';
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
