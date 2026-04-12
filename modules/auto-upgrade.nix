{ config, lib, ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "github:DanielMSchmidt/homelab";
    dates = "04:00";
    allowReboot = true;
    rebootWindow = { lower = "04:00"; upper = "05:00"; };
  };
}
