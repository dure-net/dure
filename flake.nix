{
  description = "dure - dure host and user key material";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    tincr = {
      url = "github:Mic92/tincr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      tincr,
    }:
    let
      # All loading logic lives in ./default.nix, which also works
      # without flakes: import <dure> { inherit lib; }
      data = import ./. { inherit (nixpkgs) lib; };
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      inherit (data) hosts users;

      lib = forAllSystems (system: import ./lib { inherit (nixpkgs.legacyPackages.${system}) lib; });

      nixosModules = {
        ca = ./modules/ca;
        naru = {
          imports = [
            tincr.nixosModules.tincr
            ./modules/naru/nixos.nix
          ];
        };
      };

      darwinModules = {
        ca = ./modules/ca;
        tincr = ./modules/tincr/darwin.nix;
        naru = { pkgs, ... }: {
          imports = [
            ./modules/tincr/darwin.nix
            ./modules/naru/darwin.nix
          ];
          services.tincr.package =
            nixpkgs.lib.mkDefault
              tincr.packages.${pkgs.stdenv.hostPlatform.system}.tincd;
        };
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.gum
              tincr.packages.${system}.tincd # sptps_keypair
            ];
          };
        }
      );

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./packages.nix {
          inherit (pkgs)
            coreutils
            gnutar
            gzip
            lib
            runCommand
            writeText
            ;
        }
        // {
          # wizards: nix run .#add-host / .#remove-host
          add-host = pkgs.writeShellApplication {
            name = "add-host";
            runtimeInputs = [
              pkgs.gum
              pkgs.git
              tincr.packages.${system}.tincd # sptps_keypair
            ];
            text = builtins.readFile ./scripts/add-host;
          };
          remove-host = pkgs.writeShellApplication {
            name = "remove-host";
            runtimeInputs = [
              pkgs.gum
              pkgs.git
            ];
            text = builtins.readFile ./scripts/remove-host;
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lintErrors = import ./checks/lint.nix {
            inherit (nixpkgs) lib;
            root = ./.;
            inherit (data) hosts users;
          };
        in
        {
          eval = pkgs.runCommand "dure-eval" { } ''
            ${builtins.deepSeq data "true"}
            touch $out
          '';
          lint =
            if lintErrors == [ ] then
              pkgs.runCommand "dure-lint" { } "touch $out"
            else
              throw "dure lint failed:\n${nixpkgs.lib.concatStringsSep "\n" lintErrors}";
        }
      );

      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.naru
          {
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "tmpfs";
              fsType = "tmpfs";
            };
            networking.hostName = "example";
            networking.naru = {
              nodename = "hotdog";
              ed25519PrivateKeyFile = "/var/src/secrets/tinc.naru.ed25519_key.priv";
            };
            system.stateVersion = "24.05";
          }
        ];
      };
    };
}
