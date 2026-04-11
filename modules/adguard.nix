{ ... }:
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
      };
    };
  };

  networking.firewall = {
    allowedTCPPorts = [ 53 3000 ];
    allowedUDPPorts = [ 53 ];
  };
}
