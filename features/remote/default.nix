{
  flake.modules.nixos.remote = {
    imports = [
      ./builder.nix
      ./desktop.nix
      ./sshd.nix
    ];
  };

  flake.modules.darwin.remote.home-manager.sharedModules = [ ./darwin-ssh.nix ];

  flake.modules.homeManager.remote.imports = [
    ./rdp.nix
    ./ssh.nix
  ];
}
