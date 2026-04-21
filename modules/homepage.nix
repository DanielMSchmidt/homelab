{ config, lib, ... }:
let
  domain = config.homelab.domain;
in
{
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    environmentFile = "/etc/nixos/secrets/homepage.env";

    settings = {
      title = "Homelab";
      theme = "dark";
      color = "slate";
      headerStyle = "clean";
    };

    services = [
      {
        "Services" = [
          {
            "Home Assistant" = {
              icon = "home-assistant";
              href = "https://hass.${domain}";
              description = "Home automation";
            };
          }
          {
            "Norish" = {
              icon = "mdi-food-apple";
              href = "https://norish.${domain}";
              description = "Recipe manager";
            };
          }
        ];
      }
      {
        "Security" = [
          {
            "AdGuard Home" = {
              icon = "adguard-home";
              href = "https://adguard.${domain}";
              description = "DNS-level ad & malware blocking";
              widget = {
                type = "adguard";
                url = "http://localhost:3000";
                username = "admin";
                password = "{{HOMEPAGE_VAR_ADGUARD_PASSWORD}}";
              };
            };
          }
          {
            "CrowdSec" = {
              icon = "crowdsec";
              href = "https://app.crowdsec.net";
              description = "Intrusion detection & prevention";
              widget = {
                type = "crowdsec";
                url = "http://localhost:8080";
                username = "{{HOMEPAGE_VAR_CROWDSEC_USERNAME}}";
                password = "{{HOMEPAGE_VAR_CROWDSEC_PASSWORD}}";
              };
            };
          }
        ];
      }
      {
        "Gaming" = [
          {
            "Minecraft" = {
              icon = "minecraft";
              description = "Bedrock-compatible Minecraft server";
            };
          }
        ];
      }
    ];

    widgets = [
      { resources = { cpu = true; memory = true; disk = "/"; }; }
      { search = { provider = "duckduckgo"; target = "_blank"; }; }
    ];
  };

  networking.firewall.allowedTCPPorts = [ 8082 ];
}
