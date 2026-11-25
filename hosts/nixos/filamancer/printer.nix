{ pkgs, ... }:
let
  mcuFirmware = pkgs.klipper-firmware.override {
    mcu = "profi3dmaker";
    firmwareConfig = ./klipper-mcu.config;
  };

  # The stock firmware runs 134.4 steps/mm on X and Y, 1055.959 on Z and 204.3
  # on E. That matches 1/8 microstepping on 200 step motors, so the rotation
  # distance is 1600 / steps per mm.
  stepper =
    {
      step,
      dir,
      enable,
      rotationDistance,
    }:
    {
      step_pin = step;
      dir_pin = dir;
      enable_pin = "!${enable}";
      microsteps = 8;
      rotation_distance = rotationDistance;
    };
in
{
  carbos.firmware.devices.printer = {
    description = "Profi3DMaker printer board";
    package = mcuFirmware;
    method.avrIsp = {
      programmer = "pickit_basic_isp";
      programmerUsbId = "04d8:9055";
      part = "m1281";
      fuses = {
        low = "f7";
        high = "99";
        extended = "f7";
      };
      image = "klipper.elf";
      stopUnits = [ "klipper.service" ];
    };
  };

  services.klipper = {
    enable = true;
    user = "moonraker";
    group = "moonraker";
    settings = {
      mcu = {
        serial = "/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AH01N2JA-if00-port0";
        baud = 250000;
        # DTR does not reach the reset pin.
        restart_method = "command";
      };

      printer = {
        kinematics = "cartesian";
        max_velocity = 200;
        max_accel = 1000;
        max_z_velocity = 5;
        max_z_accel = 50;
      };

      # The endstops pull low when triggered. The board has its own pull-ups.
      stepper_x =
        stepper {
          step = "PA0";
          dir = "PD0";
          enable = "PC0";
          rotationDistance = "11.904762";
        }
        // {
          endstop_pin = "!PG0";
          position_endstop = 0;
          position_max = 400;
          homing_speed = 25;
        };

      stepper_y =
        stepper {
          step = "PA1";
          dir = "PD1";
          enable = "PC1";
          rotationDistance = "11.904762";
        }
        // {
          endstop_pin = "!PG1";
          position_endstop = 260;
          position_max = 260;
          homing_speed = 25;
        };

      stepper_z =
        stepper {
          step = "PA2";
          dir = "PE2";
          enable = "PC2";
          rotationDistance = "1.515210";
        }
        // {
          endstop_pin = "!PG2";
          position_endstop = 0;
          position_max = 190;
          homing_speed = 5;
        };

      extruder =
        stepper {
          step = "PA3";
          dir = "PB7";
          enable = "PC3";
          rotationDistance = "7.831620";
        }
        // {
          nozzle_diameter = 0.4;
          filament_diameter = 1.75;
          heater_pin = "PE4";
          sensor_type = "EPCOS 100K B57560G104F";
          sensor_pin = "PF0";
          # Placeholders until PID_CALIBRATE.
          control = "pid";
          pid_kp = 22.2;
          pid_ki = 1.08;
          pid_kd = 114;
          min_temp = 0;
          max_temp = 250;
        };

      heater_bed = {
        heater_pin = "PE3";
        sensor_type = "EPCOS 100K B57560G104F";
        sensor_pin = "PF2";
        control = "watermark";
        min_temp = 0;
        max_temp = 110;
      };

      fan.pin = "PB5";

      # The stock firmware runs it while a driver is enabled, plus 60 s.
      "controller_fan board" = {
        pin = "PB6";
        idle_timeout = 60;
      };

      virtual_sdcard.path = "/var/lib/moonraker/gcodes";
      display_status = { };
      pause_resume = { };
      exclude_object = { };
    };
  };

  services.moonraker = {
    enable = true;
    settings.authorization.trusted_clients = [
      "127.0.0.0/8"
      "::1/128"
    ];
  };
}
