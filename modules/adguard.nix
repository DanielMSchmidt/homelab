{ config, lib, ... }:
let
  nucIp = config.homelab.lanAddress;
  domain = config.homelab.domain;
in
{
  services.adguardhome = {
    enable = true;
    # Allow the web UI to persist filter/block list changes at runtime.
    # The settings below only apply on first boot or after clearing AdGuard's state.
    mutableSettings = true;
    settings = {
      http.address = "0.0.0.0:3000";
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [
          "1.1.1.1"
          "9.9.9.9"
          "8.8.8.8"
        ];
        # Local DNS rewrites — devices on the LAN resolve to NUC directly,
        # bypassing Cloudflare. Same URLs work both locally and remotely.
        rewrites = [
          { domain = "*.home.lan"; answer = nucIp; }
          { domain = "adguard.${domain}"; answer = nucIp; }
          { domain = "hass.${domain}"; answer = nucIp; }
          { domain = "home.${domain}"; answer = nucIp; }
        ];
      };
    };
  };

  networking.firewall = {
    allowedTCPPorts = [ 53 3000 ];
    allowedUDPPorts = [ 53 ];
  };
}
