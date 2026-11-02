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

    amdGpu =
      method "Flash a Navi3x VBIOS through the PSP bootloader, in a boot that keeps the GPU off amdgpu."
        {
          pciId = mkOption {
            type = types.strMatching "[0-9a-f]{4}:[0-9a-f]{4}";
            example = "1002:744c";
            description = "The vendor and device ID of the GPU.";
          };
          subsystemId = mkOption {
            type = types.strMatching "[0-9a-f]{4}:[0-9a-f]{4}";
            example = "1043:0506";
            description = "The subsystem vendor and device ID, which tell the board apart.";
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

  gpus = lib.filter (device: device.method ? amdGpu) (lib.attrValues cfg.devices);
  flashBoot = "firmware-flash";

  manifest = json.generate "firmware.json" {
    esp = "${config.boot.loader.efi.efiSysMountPoint}/firmware";
    state = "/var/lib/firmware-flash";
    inherit flashBoot;
    devices = lib.mapAttrs (_: device: {
      inherit (device) description version method;
      package = "${device.package}";
    }) cfg.devices;
  };

  firmware = pkgs.writeShellApplication {
    name = "firmware";
    runtimeInputs = [
      config.services.fwupd.package
      pkgs.amd-psp-flash
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

  config = lib.mkMerge [
    { environment.systemPackages = [ firmware ]; }

    # The PSP bootloader only takes a VBIOS update until a driver loads its
    # secure OS. This boot keeps the GPU on pci-stub and stops short of the
    # desktop, flashes, then reboots into the default entry.
    (lib.mkIf (gpus != [ ]) {
      specialisation.${flashBoot}.configuration = {
        boot.kernelParams = [
          "pci-stub.ids=${lib.concatMapStringsSep "," (gpu: gpu.method.amdGpu.pciId) gpus}"
          "systemd.unit=${flashBoot}.target"
        ];
        boot.plymouth.enable = lib.mkForce false;
      };

      systemd.targets.${flashBoot} = {
        description = "Firmware flash boot";
        requires = [ "multi-user.target" ];
        wants = [ "${flashBoot}.service" ];
        after = [ "multi-user.target" ];
        unitConfig.AllowIsolate = true;
      };

      systemd.services.${flashBoot} = {
        description = "Flash pending firmware";
        after = [ "multi-user.target" ];
        unitConfig = {
          SuccessAction = "reboot";
          FailureAction = "reboot";
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe firmware} run-pending";
          StandardOutput = "journal+console";
          StandardError = "journal+console";
          # A killed stream leaves the inactive slot invalid, never the
          # active one, so the bound only has to catch a hung bootloader.
          TimeoutStartSec = "2h";
        };
      };
    })
  ];
}
