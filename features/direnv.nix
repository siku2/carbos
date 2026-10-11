{
  flake.modules.homeManager.direnv =
    { config, ... }:
    {
      imports = [ ./_options.nix ];

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        config.whitelist.prefix = [ config.carbos.user.projectsDirectory ];
      };
    };
}
