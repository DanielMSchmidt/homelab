{
  description = "NixOS homelab on Intel NUC";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, ... }:
  let
    linuxSystem = "x86_64-linux";
    linuxPkgs = import nixpkgs { system = linuxSystem; };
    forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
  in
  {
    nixosConfigurations.nuc = nixpkgs.lib.nixosSystem {
      system = linuxSystem;
      modules = [
        disko.nixosModules.disko
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
          ./hosts/nuc
        ];
      };
    };

    checks.${linuxSystem} = {
      adguard = linuxPkgs.nixosTest (import ./tests/adguard-test.nix);
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
