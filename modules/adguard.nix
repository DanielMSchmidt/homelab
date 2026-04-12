{ config, lib, ... }:
let
  nucIp = config.homelab.lanAddress;
  domain = config.homelab.domain;
in
{
  services.adguardhome = {
    enable = true;
    # Immutable — NixOS config is the source of truth. Changes via the web UI
    # are overwritten on every deploy. Edit this file instead.
    mutableSettings = false;
    settings = {
      users = [
        {
          name = "admin";
          # bcrypt hash — safe to commit (not reversible)
          password = "$2b$12$lzdgdpcznbAEDLKDIxGsyer2dRXHHX28jODLSkxraAD4qFiFuACP6";
        }
      ];
      http.address = "0.0.0.0:3000";
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [
          "1.1.1.1"
          "9.9.9.9"
          "8.8.8.8"
        ];
        bootstrap_dns = [
          "1.1.1.1"
          "9.9.9.9"
        ];
      };
      # Local DNS rewrites — devices on the LAN resolve to NUC directly,
      # bypassing Cloudflare. Same URLs work both locally and remotely.
      filtering = {
        rewrites = [
          { domain = "*.home.lan"; answer = nucIp; }
          { domain = "adguard.${domain}"; answer = nucIp; }
          { domain = "hass.${domain}"; answer = nucIp; }
          { domain = "home.${domain}"; answer = nucIp; }
          { domain = "fritz.box"; answer = "192.168.178.1"; }
        ];
      };
    };
  };

  networking.firewall = {
    allowedTCPPorts = [ 53 3000 ];
    allowedUDPPorts = [ 53 ];
  };
}
