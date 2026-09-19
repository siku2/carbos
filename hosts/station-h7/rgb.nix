{
  lib,
  pkgs,
  ...
}:
let
  # Controllers reload their firmware defaults on power-up and on resume, and
  # the DDR5 sticks keep their own rail alive through S3. Everything the script
  # touches holds a hardware mode once set, so a one-shot is enough and nothing
  # has to stay resident holding i2c and hidraw handles across a suspend.
  #
  # The Corsair Commander Core is absent on purpose: it exposes only Direct, a
  # software mode, so blanking it needs a resident daemon.
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
