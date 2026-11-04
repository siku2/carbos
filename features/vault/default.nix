{
  flake.modules.nixos.vault.imports = [
    ./bitwarden/nixos.nix
    ./onepassword.nix
    ./system.nix
  ];

  flake.modules.darwin.vault.imports = [
    ./bitwarden/darwin.nix
    ./onepassword.nix
    ./system.nix
  ];

  flake.modules.homeManager.vault.imports = [
    ./bitwarden/app.nix
    ./bitwarden/rbw.nix
    ./secretspec.nix
  ];
}
