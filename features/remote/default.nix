{
  flake.modules.nixos.remote = {
    imports = [
      ./builder.nix
      ./desktop.nix
      ./ssh.nix
    ];
  };

  flake.modules.homeManager.remote = ./rdp.nix;
}
