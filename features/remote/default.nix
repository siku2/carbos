{
  flake.modules.nixos.remote = {
    imports = [
      ./builder.nix
      ./ssh.nix
      ./sunshine.nix
    ];
  };
}
