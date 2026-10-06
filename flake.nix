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

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
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
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      hosts = builtins.attrNames (builtins.readDir ./hosts);
    in
    {
      # Each host pulls in whatever extra modules it needs itself.
      nixosConfigurations = lib.genAttrs hosts (
        name:
        lib.nixosSystem {
          inherit system;
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

      packages.${system}.kexec-installer = inputs.nixos-generators.nixosGenerate {
        inherit system;
        format = "kexec-bundle";
        specialArgs.bundle = {
          source = self;
          rev = self.shortRev or self.dirtyShortRev or "unknown";
          hosts = lib.mapAttrs (_: host: host.config.disko.devices.disk.main.device) self.nixosConfigurations;
        };
        modules = [
          inputs.disko.nixosModules.disko
          ./installer
        ];
      };

      formatter.${system} = treefmtEval.config.build.wrapper;

      checks.${system}.formatting = treefmtEval.config.build.check self;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          treefmtEval.config.build.wrapper
          pkgs.nil
          pkgs.nixd
        ];
      };
    };
}
