{
  description = "carbos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # CachyOS kernels and the AMD HDR module.
    chaotic = {
      url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
      inputs = {
        home-manager.follows = "home-manager";
        nixpkgs.follows = "nixpkgs-unstable";
      };
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      treefmt = pkgs: inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      hosts = builtins.attrNames (builtins.readDir ./hosts);

      # An installer only carries the hosts of its own platform.
      installerBundle = system: {
        source = "${self}";
        repo = "https://github.com/siku2/carbos.git";
        rev = self.shortRev or self.dirtyShortRev or "unknown";
        hosts = import ./installer/bundle.nix {
          inherit lib;
          configurations = lib.filterAttrs (
            _: host: host.config.nixpkgs.hostPlatform.system == system
          ) self.nixosConfigurations;
        };
      };
    in
    {
      # Each host pulls in whatever extra modules it needs itself.
      nixosConfigurations = lib.genAttrs hosts (
        name:
        lib.nixosSystem {
          specialArgs = {
            inherit inputs;
          };
          modules = [
            ./hosts/${name}
            inputs.disko.nixosModules.disko
            inputs.home-manager.nixosModules.home-manager
          ];
        }
      );

      packages = forAllSystems (
        pkgs:
        let
          bundle = installerBundle pkgs.stdenv.hostPlatform.system;
        in
        {
          carbos-install = pkgs.callPackage ./installer/package.nix { inherit bundle; };

          kexec-installer = pkgs.callPackage ./installer/kexec.nix {
            installer = lib.nixosSystem {
              modules = [
                ./installer
                {
                  nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system;
                  carbos.installer.bundle = bundle;
                }
              ];
            };
          };
        }
      );

      formatter = forAllSystems (pkgs: (treefmt pkgs).config.build.wrapper);

      checks = forAllSystems (pkgs: {
        formatting = (treefmt pkgs).config.build.check self;
        installer = pkgs.testers.runNixOSTest (import ./installer/test.nix { inherit inputs; });
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            (treefmt pkgs).config.build.wrapper
            pkgs.nil
            pkgs.nixd
          ];
        };
      });
    };
}
