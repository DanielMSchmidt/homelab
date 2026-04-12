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
      tunnels."ae02ca43-9696-4ab7-8b73-f81c943f7d72" = {
        # Credentials file created during setup via `cloudflared tunnel create`
        credentialsFile = "/etc/nixos/secrets/cloudflared-tunnel.json";
        originRequest.originServerName = config.homelab.domain;
        ingress = {
          "adguard.${config.homelab.domain}" = "http://localhost:3000";
          "hass.${config.homelab.domain}" = "http://localhost:8123";
          "home.${config.homelab.domain}" = "http://localhost:8082";
        };
        default = "http_status:404";
      };
    };
  };
}
