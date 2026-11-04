{
  config,
  inputs,
  ...
}:
{
  imports = [
    inputs.chaotic.nixosModules.default
    ./audio.nix
    ./disk.nix
    ./firmware.nix
    ./gaming.nix
    ./hardware.nix
  ]
  ++ (with inputs.self.modules.nixos; [
    agents
    ardour
    cloud
    desktop
    dev
    firefox
    firmware
    git
    kicad
    mic
    nix
    remote
    rlbot
    shell
    system
    vault
    vesktop
  ]);

  networking.hostName = "station-h7";

  # A 16:9 slice of the layout, the size of carbon-x1's screen.
  carbos.remote.desktop.output = {
    name = "Samsung Electric Company Odyssey G95NC HNTL300403";
    mode = "3840x2160@60.000";
    scale = 1.25;
  };

  home-manager.users.${config.carbos.user.login} = {
    imports = [ ./home ];
    home.stateVersion = "26.05";
  };

  system.stateVersion = "26.05";
}
