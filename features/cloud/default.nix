{
  flake.modules.homeManager.cloud.imports = [
    ./mounts.nix
    ./nextcloud/home.nix
  ];
}
