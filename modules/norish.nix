{ config, lib, pkgs, ... }:
let
  # Podman container names (used for inter-container DNS on the podman network)
  dbContainer = "norish-db";
  redisContainer = "norish-redis";
  chromeContainer = "norish-chrome";
in
{
  # Enable Podman (rootful, no Docker compat needed)
  virtualisation.podman.enable = true;

  # Create the podman network so containers can resolve each other by name
  systemd.services."podman-norish-network" = {
    description = "Create podman network for norish";
    after = [ "podman.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.podman}/bin/podman network create norish --ignore";
    };
  };

  # Persistent data directories
  systemd.tmpfiles.rules = [
    "d /var/lib/norish 0755 root root -"
    "d /var/lib/norish/postgres 0755 root root -"
    "d /var/lib/norish/uploads 0755 1000 1000 -"
    "d /var/lib/norish/redis 0755 root root -"
  ];

  virtualisation.oci-containers = {
    backend = "podman";

    containers.${dbContainer} = {
      image = "postgres:17-alpine";
      environment = {
        POSTGRES_USER = "norish";
        POSTGRES_PASSWORD = "norish";
        POSTGRES_DB = "norish";
      };
      volumes = [
        "/var/lib/norish/postgres:/var/lib/postgresql/data"
      ];
      extraOptions = [
        "--network=norish"
      ];
    };

    containers.${redisContainer} = {
      image = "redis:8.6.0";
      volumes = [
        "/var/lib/norish/redis:/data"
      ];
      extraOptions = [
        "--network=norish"
      ];
    };

    containers.${chromeContainer} = {
      image = "zenika/alpine-chrome:latest";
      cmd = [
        "--no-sandbox"
        "--remote-debugging-address=0.0.0.0"
        "--remote-debugging-port=3000"
        "--headless"
      ];
      extraOptions = [
        "--network=norish"
        "--shm-size=256m"
      ];
    };

    containers.norish = {
      image = "norishapp/norish:latest";
      ports = [ "8083:3000" ];
      environment = {
        DATABASE_URL = "postgres://norish:norish@${dbContainer}:5432/norish";
        REDIS_URL = "redis://${redisContainer}:6379";
        CHROME_WS_ENDPOINT = "ws://${chromeContainer}:3000";
        AUTH_URL = "https://norish.${config.homelab.domain}";
      };
      environmentFiles = [
        "/etc/nixos/secrets/norish-env"
      ];
      volumes = [
        "/var/lib/norish/uploads:/app/uploads"
      ];
      dependsOn = [
        dbContainer
        redisContainer
        chromeContainer
      ];
      extraOptions = [
        "--network=norish"
      ];
    };
  };

  # Make all container services wait for the network
  systemd.services."podman-${dbContainer}".after = [ "podman-norish-network.service" ];
  systemd.services."podman-${dbContainer}".requires = [ "podman-norish-network.service" ];
  systemd.services."podman-${redisContainer}".after = [ "podman-norish-network.service" ];
  systemd.services."podman-${redisContainer}".requires = [ "podman-norish-network.service" ];
  systemd.services."podman-${chromeContainer}".after = [ "podman-norish-network.service" ];
  systemd.services."podman-${chromeContainer}".requires = [ "podman-norish-network.service" ];
  systemd.services."podman-norish".after = [ "podman-norish-network.service" ];
  systemd.services."podman-norish".requires = [ "podman-norish-network.service" ];

  networking.firewall.allowedTCPPorts = [ 8083 ];
}
