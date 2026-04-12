{ config, lib, pkgs, ... }:
{
  # Custom option: SSH keys used across the system
  options.homelab.sshKeys = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "SSH public keys for the admin user.";
  };

  options.homelab.lanAddress = lib.mkOption {
    type = lib.types.str;
    default = "192.168.1.50";
    description = "NUC's static LAN IP address, used for DNS rewrites.";
  };

  # When mixing options and config in a module, config must be explicit
  config = {
    # Nix settings
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    # Locale and timezone — override in hosts/nuc/default.nix
    time.timeZone = lib.mkDefault "UTC";
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

    # SSH hardened defaults
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # Admin user — add your SSH public key in hosts/nuc/default.nix
    users.users.admin = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = config.homelab.sshKeys;
      # Fallback password for console/SSH access — change after first login
      initialPassword = "changeme";
    };

    # Allow admin to sudo without password (convenience for single-user homelab)
    security.sudo.wheelNeedsPassword = false;

    # Base firewall — individual modules add their own ports
    networking.firewall.enable = true;

    # Essential packages
    environment.systemPackages = with pkgs; [
      vim
      git
      htop
      curl
    ];
  };
}
