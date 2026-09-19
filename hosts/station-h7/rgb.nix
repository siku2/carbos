{
  lib,
  pkgs,
  ...
}:
let
  # --noautoconnect: there is no SDK server to reach, so skip the attempt and
  # the error line it logs.
  openrgb = "${lib.getExe pkgs.openrgb} --noautoconnect";

  # Controllers reload their firmware defaults on power-up and on resume, and
  # the DDR5 sticks keep their own rail alive through S3. These all hold a
  # hardware mode once set, so a one-shot is enough and nothing has to stay
  # resident holding i2c and hidraw handles across a suspend.
  #
  # Names match case-insensitively as substrings and every match is applied,
  # so one "ENE DRAM" entry covers both sticks.
  offMode = [
    "ENE DRAM"
    "ASUS TUF Radeon RX 7900 XTX Gaming OC"
    "ASUS TUF GAMING X670E-PLUS"
    "Razer Blackwidow Chroma V2"
    "Logitech G903 Wired/Wireless Gaming Mouse"
    "Candy companion chip"
  ];

  # No off mode on this one, so static black is the equivalent.
  blackStatic = [ "NZXT RGB & Fan Controller" ];

  # The Corsair Commander Core exposes only Direct, a software mode, so it
  # reverts the moment nothing drives it. Blanking it needs a resident daemon,
  # which is exactly what this module avoids.

  blank = pkgs.writeShellScript "rgb-blank" ''
    for dev in ${lib.escapeShellArgs offMode}; do
      ${openrgb} --device "$dev" --mode off || echo "could not blank $dev" >&2
    done

    for dev in ${lib.escapeShellArgs blackStatic}; do
      ${openrgb} --device "$dev" --mode static --color 000000 \
        || echo "could not blank $dev" >&2
    done
  '';

  unit = description: {
    inherit description;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = blank;
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
