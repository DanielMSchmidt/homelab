# modules/cloudflared.nix
{ config, lib, ... }:
{
  options.homelab.domain = lib.mkOption {
    type = lib.types.str;
    default = "example.com";
    description = "Your domain managed by Cloudflare.";
  };

  config = {
    services.cloudflared = {
      enable = true;
      tunnels.homelab = {
        # Credentials file created during setup via `cloudflared tunnel create`
        credentialsFile = "/etc/nixos/secrets/cloudflared-tunnel.json";
        ingress = {
          "adguard.${config.homelab.domain}" = "http://localhost:3000";
          "hass.${config.homelab.domain}" = "http://localhost:8123";
          "home.${config.homelab.domain}" = "http://localhost:8082";
          "norish.${config.homelab.domain}" = "http://localhost:8083";
        };
        default = "http_status:404";
      };
    };

    # Origin cert must be readable by cloudflared and in a default search path
    environment.etc."cloudflared/cert.pem" = {
      source = "/etc/nixos/secrets/cloudflared-cert.pem";
      mode = "0644";
    };

    # Ensure credentials file is readable by the cloudflared service
    systemd.services.cloudflared-tunnel-homelab.serviceConfig.ExecStartPre =
      "+${lib.getExe' config.services.cloudflared.package "cloudflared"} version || true";
    systemd.tmpfiles.rules = [
      "z /etc/nixos/secrets/cloudflared-tunnel.json 0644 root root -"
      "z /etc/nixos/secrets/cloudflared-cert.pem 0644 root root -"
    ];
  };
}
