{
  flake.modules.nixos.vault =
    { config, lib, ... }:
    {
      imports = [
        ./backend.nix
        ./onepassword.nix
      ];

      # niri enables gnome-keyring, which would take over SSH_AUTH_SOCK in the user manager.
      services.gnome.gcr-ssh-agent.enable = lib.mkIf (config.carbos.vault.backend == "bitwarden") false;
    };

  flake.modules.darwin.vault =
    { config, ... }:
    {
      imports = [
        ./backend.nix
        ./onepassword.nix
      ];

      # rbw-agent runs as a systemd user service.
      assertions = [
        {
          assertion = config.carbos.vault.backend != "bitwarden";
          message = "carbos.vault.backend = \"bitwarden\" only works on NixOS so far.";
        }
      ];
    };

  flake.modules.homeManager.vault.imports = [
    ./bitwarden/app.nix
    ./bitwarden/rbw.nix
    ./secretspec.nix
  ];
}
