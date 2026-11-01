{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.carbos.firmware;
  json = pkgs.formats.json { };

  image =
    description:
    mkOption {
      type = types.str;
      inherit description;
    };

  method =
    description: options:
    mkOption {
      type = types.submodule { inherit options; };
      inherit description;
    };

  methods = {
    fwupd = method "Flash with fwupdtool install-blob." {
      instanceId = mkOption {
        type = types.str;
        example = "USB\\VID_17EF&PID_A356";
        description = "The fwupd instance ID that finds the device.";
      };
      images = mkOption {
        type = types.nonEmptyListOf types.str;
        description = ''
          Images in the package to install with fwupdtool. fwupd rejects an
          image for the running slot of a dual-image device, so the order
          does not matter.
        '';
      };
    };

    samsungNvme = method "Flash a Samsung NVMe SSD with nvme-cli, picking the image like fumagician." {
      device = mkOption {
        type = types.str;
        default = "/dev/nvme0";
        description = "The NVMe controller.";
      };
    };

    xmos = method "Flash an XMOS USB audio device with xmosdfu." {
      vendorId = mkOption {
        type = types.strMatching "[0-9a-f]{4}";
        description = "USB vendor ID in hex.";
      };
      productId = mkOption {
        type = types.strMatching "[0-9a-f]{4}";
        description = "USB product ID in hex.";
      };
      image = image "The image in the package to send with xmosdfu.";
    };

    amdGpu = method "Flash an AMD GPU VBIOS with fwupdtool." {
      instanceId = mkOption {
        type = types.str;
        example = "AMD\\115-D702BS";
        description = "The fwupd instance ID that finds the GPU.";
      };
      partNumber = mkOption {
        type = types.str;
        example = "115-D702BS0-101";
        description = "The VBIOS part number, as amdgpu shows it in vbios_version.";
      };
      images = mkOption {
        type = types.nonEmptyListOf types.str;
        description = ''
          Images in the package, one for each BIOS switch position. The flash
          picks the one for the running position.
        '';
      };
    };

    esp = method "Copy the image to the ESP for the firmware setup to flash." {
      image = image "The image in the package that the firmware setup flashes.";
    };
  };

  device = types.submodule (
    { config, ... }:
    {
      options = {
        description = mkOption {
          type = types.str;
          description = "What the device is.";
        };
        package = mkOption {
          type = types.package;
          description = "The package with the firmware images.";
        };
        version = mkOption {
          type = types.str;
          default = config.package.version;
          defaultText = lib.literalExpression "package.version";
          description = "The firmware version the images install, as the device reports it.";
        };
        method = mkOption {
          type = types.attrTag methods;
          description = "How the device reports its version and gets flashed.";
        };
      };
    }
  );

  manifest = json.generate "firmware.json" {
    esp = "${config.boot.loader.efi.efiSysMountPoint}/firmware";
    devices = lib.mapAttrs (_: device: {
      inherit (device) description version method;
      package = "${device.package}";
    }) cfg.devices;
  };

  firmware = pkgs.writeShellApplication {
    name = "firmware";
    runtimeInputs = [
      config.services.fwupd.package
      pkgs.nodejs-slim
      pkgs.nvme-cli
      pkgs.xmosdfu
    ];
    text = ''
      exec node ${./firmware.ts} ${manifest} "$@"
    '';
  };
in
{
  options.carbos.firmware.devices = mkOption {
    type = types.attrsOf device;
    default = { };
    description = "Devices whose firmware the firmware command updates.";
  };

  config = {
    environment.systemPackages = [ firmware ];
  };
}
