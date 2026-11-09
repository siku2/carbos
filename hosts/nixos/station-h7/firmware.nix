{ pkgs, ... }:
let
  firmware = pkgs.device-firmware;
  bios = firmware.asus-tuf-x670e-plus;
  dock = firmware.lenovo-hybrid-dock;
  g903 = firmware.logitech-g903;
in
{
  carbos.firmware.devices = {
    bios = {
      description = "ASUS TUF GAMING X670E-PLUS BIOS";
      package = bios;
      method.esp = { inherit (bios) image; };
    };

    gpu = {
      description = "ASUS TUF RX 7900 XTX VBIOS";
      package = firmware.asus-tuf-rx7900xtx;
      method.amdGpu = {
        pciId = "1002:744c";
        subsystemId = "1043:0506";
        images = [
          "p.rom"
          "q.rom"
        ];
      };
    };

    ssd = {
      description = "Samsung 990 PRO 2TB";
      package = firmware.samsung-990-pro;
      method.samsungNvme = { };
    };

    ssl2 = {
      description = "SSL 2 MkII audio interface";
      package = firmware.ssl-2-mk2;
      method.xmos = {
        vendorId = "31e9";
        productId = "0008";
        image = "ssl2-mk2.bin";
      };
    };

    keyboard = {
      description = "Razer BlackWidow Chroma V2 keyboard";
      package = firmware.razer-blackwidow-chroma-v2;
      method.razerKeyboard.image = "bwc2.hex";
    };

    # G HUB only updates the mouse over its USB cable.
    g903 = {
      description = "Logitech G903 mouse";
      package = g903;
      version = g903.deviceVersion;
      method.fwupd = {
        instanceId = "HIDRAW\\VEN_046D&DEV_C086";
        images = [ "g903.dfu" ];
      };
    };

    # The Tier 1 hub holds Tier 2 on its port 4. The USB 2 and USB 3 halves of
    # each hub share one flash.
    dock-hub-tier1 = {
      description = "ThinkPad dock VL820 hub, tier 1";
      package = dock;
      version = dock.versions.tier1;
      method.fwupd = {
        instanceId = "USB\\VID_17EF&PID_A356";
        images = [ "vl820-tier1.bin" ];
      };
    };

    dock-hub-tier2 = {
      description = "ThinkPad dock VL820 hub, tier 2";
      package = dock;
      version = dock.versions.tier2;
      method.fwupd = {
        instanceId = "USB\\VID_17EF&PID_A357";
        images = [ "vl820-tier2.bin" ];
      };
    };

    dock-pd = {
      description = "ThinkPad dock CCG4 PD controller";
      package = dock;
      version = dock.versions.pd;
      method.fwupd = {
        instanceId = "USB\\VID_04B4&PID_5218";
        images = [
          "ccg4-fw1.cyacd"
          "ccg4-fw2.cyacd"
        ];
      };
    };
  };
}
