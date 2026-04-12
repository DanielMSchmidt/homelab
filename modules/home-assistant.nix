{ config, lib, pkgs, ... }:
{
  services.home-assistant = {
    enable = true;
    config = {
      homeassistant = {
        name = "Home";
        unit_system = "metric";
        time_zone = config.time.timeZone;
        country = "DE";
        currency = "EUR";
      };
      # Trust Caddy reverse proxy
      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" "::1" ];
      };
      # Load default integrations
      default_config = {};
    };
  };

  networking.firewall.allowedTCPPorts = [ 8123 ];
}
