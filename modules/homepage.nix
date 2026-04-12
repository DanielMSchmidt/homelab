{ config, lib, ... }:
{
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;

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
            "AdGuard Home" = {
              icon = "adguard-home";
              href = "http://adguard.home.lan";
              description = "DNS-level ad & malware blocking";
              widget = {
                type = "adguard";
                url = "http://localhost:3000";
              };
            };
          }
          {
            "Home Assistant" = {
              icon = "home-assistant";
              href = "http://hass.home.lan";
              description = "Home automation";
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
