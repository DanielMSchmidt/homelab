{ config, lib, pkgs, ... }:
let
  configDir = "/etc/crowdsec";
  dataDir = "/var/lib/crowdsec";

  crowdsecConfig = pkgs.writeText "crowdsec-config.yaml" ''
    common:
      daemonize: false
      log_media: stdout
      log_level: info
    config_paths:
      config_dir: ${configDir}/
      data_dir: ${dataDir}/data/
      simulation_path: ${configDir}/simulation.yaml
      hub_dir: ${dataDir}/hub/
      index_path: ${dataDir}/hub/.index.json
      notification_dir: ${configDir}/notifications/
      plugin_dir: ${configDir}/plugins/
      pattern_dir: ${pkgs.crowdsec}/share/crowdsec/config/patterns
    crowdsec_service:
      acquisition_path: ${configDir}/acquis.yaml
      acquisition_dir: ${configDir}/acquis.d
      parser_routines: 1
    cscli:
      output: human
    db_config:
      type: sqlite
      db_path: ${dataDir}/data/crowdsec.db
      use_wal: true
    api:
      client:
        insecure_skip_verify: false
        credentials_path: ${dataDir}/credentials/local_api_credentials.yaml
      server:
        log_level: info
        listen_uri: 127.0.0.1:8080
        profiles_path: ${configDir}/profiles.yaml
        console_path: ${dataDir}/credentials/console.yaml
        online_client:
          credentials_path: ${dataDir}/credentials/online_api_credentials.yaml
        trusted_ips:
          - 127.0.0.1
          - ::1
    prometheus:
      enabled: true
      level: full
      listen_addr: 127.0.0.1
      listen_port: 6060
  '';

  acquis = pkgs.writeText "crowdsec-acquis.yaml" ''
    source: journalctl
    journalctl_filter:
      - "_SYSTEMD_UNIT=sshd.service"
    labels:
      type: syslog
    ---
    source: file
    filenames:
      - /var/log/caddy/*.log
    labels:
      type: caddy
  '';

  simulation = pkgs.writeText "crowdsec-simulation.yaml" ''
    simulation: false
  '';

  profiles = pkgs.writeText "crowdsec-profiles.yaml" ''
    name: default_ip_remediation
    filters:
      - Alert.Remediation == true && Alert.GetScope() == "Ip"
    decisions:
      - type: ban
        duration: 4h
    on_success: break
    ---
    name: default_range_remediation
    filters:
      - Alert.Remediation == true && Alert.GetScope() == "Range"
    decisions:
      - type: ban
        duration: 4h
    on_success: break
  '';

  cscli = "${pkgs.crowdsec}/bin/cscli -c ${configDir}/config.yaml";
in
{
  environment.etc = {
    "crowdsec/config.yaml".source = crowdsecConfig;
    "crowdsec/acquis.yaml".source = acquis;
    "crowdsec/simulation.yaml".source = simulation;
    "crowdsec/profiles.yaml".source = profiles;
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 crowdsec crowdsec -"
    "d ${dataDir}/data 0750 crowdsec crowdsec -"
    "d ${dataDir}/hub 0750 crowdsec crowdsec -"
    "d ${dataDir}/credentials 0750 crowdsec crowdsec -"
    "d ${configDir}/acquis.d 0755 root root -"
    "d ${configDir}/notifications 0755 root root -"
    "d ${configDir}/plugins 0755 root root -"
    "d /var/log/caddy 0755 caddy caddy -"
  ];

  users.users.crowdsec = {
    isSystemUser = true;
    group = "crowdsec";
    extraGroups = [ "systemd-journal" ];
    home = dataDir;
  };
  users.groups.crowdsec = {};

  systemd.services.crowdsec = {
    description = "CrowdSec Security Engine";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      Type = "notify";
      User = "crowdsec";
      Group = "crowdsec";
      ExecStartPre = let
        initScript = pkgs.writeShellScript "crowdsec-init" ''
          # Create placeholder credential files so cscli doesn't fail on missing refs
          for f in local_api_credentials.yaml online_api_credentials.yaml console.yaml; do
            if [ ! -f ${dataDir}/credentials/$f ]; then
              echo "{}" > ${dataDir}/credentials/$f
              chown crowdsec:crowdsec ${dataDir}/credentials/$f
            fi
          done

          # Update hub index and install collections on first run
          if [ ! -f ${dataDir}/hub/.index.json ]; then
            ${cscli} hub update
            ${cscli} collections install crowdsecurity/linux
            ${cscli} collections install crowdsecurity/sshd
            ${cscli} collections install crowdsecurity/caddy
          fi

          # Register machine if not already registered
          if ! grep -q "login:" ${dataDir}/credentials/local_api_credentials.yaml 2>/dev/null; then
            ${cscli} machines add nuc --auto --force
          fi

          # Register with CAPI (community blocklists) if not done
          if ! grep -q "login:" ${dataDir}/credentials/online_api_credentials.yaml 2>/dev/null; then
            ${cscli} capi register || true
          fi

          # Ensure all data files are owned by crowdsec (init runs as root)
          chown -R crowdsec:crowdsec ${dataDir}
        '';
      in "+${initScript}";
      ExecStart = "${pkgs.crowdsec}/bin/crowdsec -c ${configDir}/config.yaml";
      Restart = "always";
      RestartSec = 60;
      ReadWritePaths = [ dataDir "/var/log/caddy" ];
      SupplementaryGroups = [ "systemd-journal" ];
    };
  };

  systemd.services.crowdsec-firewall-bouncer = {
    description = "CrowdSec Firewall Bouncer";
    wantedBy = [ "multi-user.target" ];
    after = [ "crowdsec.service" ];
    requires = [ "crowdsec.service" ];

    serviceConfig = {
      Type = "notify";
      ExecStart = "${pkgs.crowdsec-firewall-bouncer}/bin/cs-firewall-bouncer -c /etc/nixos/secrets/crowdsec-bouncer.yaml";
      Restart = "always";
      RestartSec = 10;
      AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
      CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
    };
  };

  environment.systemPackages = [ pkgs.crowdsec ];
}
