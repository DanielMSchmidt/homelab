{ config, ... }:
let
  domain = config.homelab.domain;
  dashboardAuth = ''
    basicauth {
      883fc68b50662de7 $2a$14$Cm547Lqka36UNACuhfnC7uOYrYbBRUf4G/AjO6JOaji1XN3u8ZZFS
    }
    reverse_proxy localhost:8082
  '';
in
{
  services.caddy = {
    enable = true;

    globalConfig = ''
      servers {
        trusted_proxies static ::1 127.0.0.1
      }
    '';

    virtualHosts."http://adguard.home.lan".extraConfig = ''
      reverse_proxy localhost:3000
    '';

    virtualHosts."http://hass.home.lan".extraConfig = ''
      reverse_proxy localhost:8123
    '';

    virtualHosts."http://home.home.lan".extraConfig = dashboardAuth;

    virtualHosts."http://home.${domain}".extraConfig = dashboardAuth;

    virtualHosts."http://norish.home.lan".extraConfig = ''
      reverse_proxy localhost:8083
    '';
  };

  # Allow CrowdSec (in caddy group) to read Caddy access logs
  systemd.services.caddy.serviceConfig.UMask = "0027";

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
