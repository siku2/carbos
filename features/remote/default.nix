{
  flake.modules.nixos.remote = {
    imports = [
      ./ssh.nix
      ./sunshine.nix
    ];
  };
}
