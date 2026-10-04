{
  config,
  pkgs,
  ...
}:
{
  programs.fish.enable = true;

  # Without this, the password options only apply when the account is created.
  users.mutableUsers = false;

  users.users.${config.carbos.user.login} = {
    isNormalUser = true;
    description = config.carbos.user.fullName;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
      "input"
      # For the rtprio rlimit, so PipeWire clients go realtime without rtkit.
      "pipewire"
    ];
    # No password at all. PAM only accepts this where nullok is set, which
    # covers greetd and the lock screen but not sudo or polkit.
    hashedPassword = "";
  };

  security.sudo.wheelNeedsPassword = false;

  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${config.carbos.user.login} = import ../homes/simon;
  };
}
