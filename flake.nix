{
  description = "NixOS homelab on Intel NUC";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    playit-nixos-module = {
      url = "github:pedorich-n/playit-nixos-module";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, playit-nixos-module, ... }:
  let
    linuxSystem = "x86_64-linux";
    unstablePkgs = import nixpkgs-unstable { system = linuxSystem; };
    overlay = final: prev: {
      crowdsec-firewall-bouncer = unstablePkgs.crowdsec-firewall-bouncer;
    };
    linuxPkgs = import nixpkgs { system = linuxSystem; overlays = [ overlay ]; };
    forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
  in
  {
    nixosConfigurations.nuc = nixpkgs.lib.nixosSystem {
      system = linuxSystem;
      modules = [
        { nixpkgs.overlays = [ overlay ]; }
        disko.nixosModules.disko
        playit-nixos-module.nixosModules.default
        ./hosts/nuc
      ];
    };

    colmena = {
      meta = {
        nixpkgs = linuxPkgs;
      };
      nuc = {
        deployment = {
          targetHost = "nuc";
          targetUser = "admin";
          buildOnTarget = true;
        };
        imports = [
          disko.nixosModules.disko
          playit-nixos-module.nixosModules.default
          ./hosts/nuc
        ];
      };
    };

    checks.${linuxSystem} = {
      adguard = linuxPkgs.nixosTest (import ./tests/adguard-test.nix);
      caddy = linuxPkgs.nixosTest (import ./tests/caddy-test.nix);
      minecraft = linuxPkgs.nixosTest (import ./tests/minecraft-test.nix {
        playitModule = playit-nixos-module.nixosModules.default;
      });
      integration = linuxPkgs.nixosTest (import ./tests/integration-test.nix {
        playitModule = playit-nixos-module.nixosModules.default;
      });
    };

    devShells = forAllSystems (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        default = pkgs.mkShell {
          packages = with pkgs; [
            colmena
            nil
            nixpkgs-fmt
          ];
        };
      }
    );
  };
}
