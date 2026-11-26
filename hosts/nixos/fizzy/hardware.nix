{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";

  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 20;
    };
    efi.canTouchEfiVariables = true;
  };

  hardware = {
    bluetooth.enable = true;
    cpu.intel.updateMicrocode = true;
    enableRedistributableFirmware = true;
    graphics = {
      enable = true;
      extraPackages = [ pkgs.intel-media-driver ];
    };
    sensor.iio.enable = true;
  };

  # The touch button below the screen sends the Windows key. Android treats
  # KEY_HOMEPAGE as its home button.
  services.udev.extraHwdb = ''
    evdev:atkbd:dmi:bvn*:bvr*:bd*:svnPanasonicCorporation:pnFZM1*:*
     KEYBOARD_KEY_db=homepage
  '';
}
