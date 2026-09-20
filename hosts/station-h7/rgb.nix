{
  lib,
  pkgs,
  ...
}:
let
  # Controllers and DDR5 RGB restore state on resume, so one-shot is enough.
  # Corsair Commander Core has no persistent lighting storage, so the only way
  # to blank it is HOST mode, which leaves its pump and fan curve unmanaged.
  blank = pkgs.writeShellApplication {
    name = "rgb-blank";
    runtimeInputs = [ pkgs.openrgb ];
    text = builtins.readFile ./rgb-blank.sh;
  };

  unit = description: {
    inherit description;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe blank;
    };
  };
in
{
  environment.systemPackages = [ pkgs.openrgb ];
  services.udev.packages = [ pkgs.openrgb ];

  boot.kernelModules = [
    "i2c-dev"
    "i2c-piix4"
  ];

  systemd.services = {
    # After=sleep.target puts this on the resume side, and sleep.target is not
    # in the transaction at boot, so one unit covers both.
    rgb-blank = lib.recursiveUpdate (unit "Blank RGB at boot and on resume") {
      after = [ "sleep.target" ];
      wantedBy = [
        "multi-user.target"
        "sleep.target"
      ];
    };

    rgb-blank-pre-sleep = lib.recursiveUpdate (unit "Blank RGB before suspend") {
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
    };
  };
}
