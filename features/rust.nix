{
  flake.modules.homeManager.rust =
    { pkgs, ... }:
    {
      home = {
        packages = [ pkgs.cargo-clean-all ];
        shellAliases.xtask = "cargo run --quiet --bin xtask --";
      };
    };
}
