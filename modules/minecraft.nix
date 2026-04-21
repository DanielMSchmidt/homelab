{ config, lib, pkgs, ... }:
let
  # GeyserMC standalone — translates Bedrock (Switch) protocol to Java
  geyserVersion = "2.9.5";
  geyserBuild = "1117";
  geyserJar = pkgs.fetchurl {
    url = "https://download.geysermc.org/v2/projects/geyser/versions/${geyserVersion}/builds/${geyserBuild}/downloads/standalone";
    hash = "sha256-6eXf/udKlf/IE3lWwWl0lDYEWjqZtwLNAoCew7vXMk8=";
  };

  geyserConfig = pkgs.writeText "geyser-config.yml" ''
    bedrock:
      address: 0.0.0.0
      port: 19132
      motd1: "Homelab Minecraft"
      motd2: ""
    remote:
      address: 127.0.0.1
      port: 25565
      auth-type: online
    command-suggestions: true
    passthrough-motd: true
    passthrough-player-counts: true
    above-bedrock-nether-building: true
  '';

  # playit.gg agent — tunnels UDP for remote Bedrock access
  playitVersion = "0.17.1";
  playitBin = pkgs.stdenv.mkDerivation {
    pname = "playit";
    version = playitVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/playit-cloud/playit-agent/releases/download/v${playitVersion}/playit-linux-amd64";
      hash = "sha256-541GPZOqHj7Dagbe1aH0/oeZBf3OuGXfj0zvYST4pVU=";
    };
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/playit
      chmod +x $out/bin/playit
    '';
  };
in
{
  # ── Java Minecraft Server (NixOS built-in module) ──────────────
  services.minecraft-server = {
    enable = true;
    eula = true;
    package = pkgs.minecraft-server;

    jvmOpts = "-Xms4G -Xmx4G";

    serverProperties = {
      server-port = 25565;
      # Bind to localhost only — GeyserMC and direct LAN Java clients connect here
      server-ip = "127.0.0.1";
      motd = "Homelab Minecraft";
      max-players = 10;
      gamemode = "survival";
      difficulty = "normal";
      # Must be false for GeyserMC to proxy Bedrock players
      # Security is handled by the whitelist + GeyserMC's Xbox Live auth (auth-type: online)
      online-mode = false;
      white-list = true;
      enforce-whitelist = true;
    };

    # Whitelist — add players here as "name" = "offline-uuid"
    # For Bedrock players via GeyserMC, the name is prefixed with "."
    # Generate offline UUID: https://minecraft-serverlist.com/tools/offline-uuid
    whitelist = {
      # Example: ".SwitchPlayerName" = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx";
    };
  };

  # ── GeyserMC Standalone (Bedrock → Java proxy) ────────────────
  systemd.tmpfiles.rules = [
    "d /var/lib/geyser 0750 geyser geyser -"
  ];

  users.users.geyser = {
    isSystemUser = true;
    group = "geyser";
    home = "/var/lib/geyser";
  };
  users.groups.geyser = {};

  systemd.services.geyser = {
    description = "GeyserMC Bedrock-to-Java Proxy";
    wantedBy = [ "multi-user.target" ];
    after = [ "minecraft-server.service" ];
    requires = [ "minecraft-server.service" ];

    serviceConfig = {
      Type = "simple";
      User = "geyser";
      Group = "geyser";
      WorkingDirectory = "/var/lib/geyser";
      ExecStartPre = "${pkgs.coreutils}/bin/cp --no-preserve=mode ${geyserConfig} /var/lib/geyser/config.yml";
      ExecStart = "${pkgs.jre_headless}/bin/java -Xms256m -Xmx256m -jar ${geyserJar}";
      Restart = "always";
      RestartSec = 15;
    };
  };

  # ── playit.gg Agent (UDP tunnel for remote access) ────────────
  # Secret created during setup: sign up at playit.gg, create UDP tunnel,
  # save token to /etc/nixos/secrets/playit-secret.toml
  systemd.services.playit = {
    description = "playit.gg Tunnel Agent";
    wantedBy = [ "multi-user.target" ];
    after = [ "geyser.service" "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${playitBin}/bin/playit --secret_path /etc/nixos/secrets/playit-secret.toml";
      Restart = "always";
      RestartSec = 15;
      DynamicUser = true;
    };
  };

  # ── Firewall ──────────────────────────────────────────────────
  networking.firewall.allowedUDPPorts = [ 19132 ];
}
