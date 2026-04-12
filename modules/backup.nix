# modules/backup.nix — restic backups to USB stick
{ config, lib, pkgs, ... }:
{
  # Mount the USB backup drive
  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-label/backup";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=5" ];
  };

  # Restic backup password stored on-device
  # Created during setup or manually: echo "your-password" | sudo tee /etc/nixos/secrets/restic-password
  services.restic.backups.usb = {
    repository = "/mnt/backup/restic";
    passwordFile = "/etc/nixos/secrets/restic-password";

    paths = [
      "/var/lib/AdGuardHome"
      "/var/lib/hass"
      "/var/lib/norish"
      "/etc/nixos/secrets"
    ];

    # Daily at 3am, keep 7 daily + 4 weekly + 6 monthly snapshots
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];

    # Initialize the repo if it doesn't exist
    initialize = true;
  };

  environment.systemPackages = [ pkgs.restic ];
}
