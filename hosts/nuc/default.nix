{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./disk.nix
    ../../modules/common.nix
    ../../modules/adguard.nix
    ../../modules/caddy.nix
    ../../modules/home-assistant.nix
    ../../modules/cloudflared.nix
    ../../modules/homepage.nix
    ../../modules/norish.nix
    ../../modules/auto-upgrade.nix
    ../../modules/crowdsec.nix
    ../../modules/backup.nix
    ../../modules/minecraft.nix
  ];

  # ============================================================
  # CUSTOMIZE THESE VALUES FOR YOUR SETUP
  # ============================================================

  networking.hostName = "nuc";

  # Static IP — change interface name and address to match your LAN
  # Find your interface name with: ip link
  networking.interfaces.enp100s0.ipv4.addresses = [{
    address = "192.168.178.83";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.178.1";
  # Points to AdGuard Home on localhost — use "1.1.1.1" until AdGuard is running
  networking.nameservers = [ "127.0.0.1" ];

  time.timeZone = "Europe/Berlin";

  # Add your SSH public key(s) here
  homelab.sshKeys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD7qgSYyYFOSJn0CxHoprbfD8MSVLRkjixC/bvnvrs9E0ifF/6hrNr9F3PXFip4veSMru6uAPv8otmaqW89N8YnNlKG+Vrch6pPDNc+RtgVi7R++qXT1kb3Q8vRdSA5D9krAlcgauzvFWcgkfDCyZCYDqtequrCLoPVX7mfdkEW9Bl98y264VDJwUEuoOHqWvC1eh4ZEu0iIbG7UF1xKEJORoBeB35rf+t39UfWLxxGac3WluwClqgbkQlDMr6o3MtxDz9Jv7YpyKWHuVTOmA+VkMASH0ppSHOoLn3Pdl7gXliicqpCOqeQ824GR15RDQW4Gnil6EYNPjCyuXVkeWTkB6gl/kEhvChmPmGCs+K83YiuSfFBHIxMKYXrj1yv3nJJwvtM91uoPAGPVP1N7JvB7eFQmhUFjUL9fFcmHfHZ+NDzkgxCGd/SOX6ppUhMUBf9GbfUvnTSyXKJ1J1Hky2cg+r9E0H1xkhwD/DGGj5JBkEq+czkhqg9OybB7AtCqkk= dschmidt@dschmidt-C02FK2YEMD6R"
  ];

  # NUC's LAN IP — must match the static IP above
  homelab.lanAddress = "192.168.178.83";

  # Your Cloudflare-managed domain
  homelab.domain = "danielmschmidt.de";

  # ============================================================

  system.stateVersion = "24.11";
}
