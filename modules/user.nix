{
  config,
  pkgs,
  ...
}:
{
  programs.fish.enable = true;

  users.users.${config.carbos.user.login} = {
    isNormalUser = true;
    description = config.carbos.user.fullName;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
      "input"
    ];
    initialHashedPassword = "$6$eDAB8oLyIaVyxmI3$yoi5I1B8Q/EMAScuHKSOn4OU5WrNQd3a/QPl9mMTfpMFtnBgoeN.9Wyo3gYIuHc6bUCmmsx43FY.Tv3nQr5kJ/";
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${config.carbos.user.login} = import ../homes/simon;
  };
}
