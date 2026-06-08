{ config, ... }:
let
  domain = config.homelab.domain;
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

    virtualHosts."http://home.home.lan".extraConfig = ''
      reverse_proxy localhost:8082
    '';

    virtualHosts."http://home.${domain}".extraConfig = ''
      reverse_proxy localhost:8082
    '';

    virtualHosts."http://norish.home.lan".extraConfig = ''
      reverse_proxy localhost:8083
    '';
  };

  # Allow CrowdSec (in caddy group) to read Caddy access logs
  systemd.services.caddy.serviceConfig.UMask = "0027";

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
