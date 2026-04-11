{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./disk.nix
    ../../modules/common.nix
    ../../modules/adguard.nix
    ../../modules/caddy.nix
  ];

  # ============================================================
  # CUSTOMIZE THESE VALUES FOR YOUR SETUP
  # ============================================================

  networking.hostName = "nuc";

  # Static IP — change to match your LAN
  networking.interfaces.eno1.ipv4.addresses = [{
    address = "192.168.1.50";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.1.1";
  # Points to AdGuard Home on localhost — use "1.1.1.1" until AdGuard is running
  networking.nameservers = [ "127.0.0.1" ];

  time.timeZone = "America/New_York";

  # Add your SSH public key(s) here
  homelab.sshKeys = [
    # "ssh-ed25519 AAAA... you@laptop"
  ];

  # ============================================================

  system.stateVersion = "24.11";
}
