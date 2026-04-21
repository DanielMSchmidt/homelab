{ pkgs, ... }:
{
  name = "minecraft";

  nodes.machine = { pkgs, lib, ... }: {
    imports = [
      ../modules/common.nix
      ../modules/minecraft.nix
    ];

    homelab.sshKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest test@test" ];

    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [ "minecraft-server" ];

    # Disable playit.gg in test — needs internet access to connect to playit servers
    systemd.services.playit.enable = lib.mkForce false;

    # Give the VM enough memory for the Minecraft server
    virtualisation.memorySize = 4096;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Java Minecraft server starts and listens
    machine.wait_for_unit("minecraft-server.service", timeout=180)
    machine.wait_for_open_port(25565, timeout=180)

    # GeyserMC starts and listens on Bedrock port
    machine.wait_for_unit("geyser.service", timeout=120)
    machine.wait_for_open_port(19132, timeout=120)
  '';
}
