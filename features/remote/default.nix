{
  flake.modules.nixos.remote = {
    imports = [
      ./builder.nix
      ./desktop.nix
      ./sshd.nix
    ];
  };

  flake.modules.homeManager.remote.imports = [
    ./rdp.nix
    ./ssh.nix
  ];
}
