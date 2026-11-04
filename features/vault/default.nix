{
  flake.modules.nixos.vault.imports = [
    ./bitwarden/nixos.nix
    ./module.nix
    ./onepassword.nix
  ];

  flake.modules.darwin.vault.imports = [
    ./bitwarden/darwin.nix
    ./module.nix
    ./onepassword.nix
  ];

  flake.modules.homeManager.vault.imports = [
    ./bitwarden/app.nix
    ./bitwarden/rbw.nix
    ./secretspec.nix
  ];
}
