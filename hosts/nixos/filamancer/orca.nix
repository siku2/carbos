{
  config,
  lib,
  pkgs,
  ...
}:
let
  machine = import ./machine.nix;
  inherit (machine) bed str;

  url = "https://${config.networking.fqdn}";
  printerName = "Profi3DMaker ${str machine.nozzle} nozzle";
  filamentName = "Carbon PLA @Profi3DMaker";
  processName = "0.20mm Standard @Profi3DMaker";

  # Orca keeps every machine limit twice, for normal and stealth mode.
  limit = x: [
    (str x)
    (str x)
  ];

  user = name: inherits: {
    inherit name inherits;
    from = "User";
    instantiation = "true";
  };

  # Orca takes every value as text, so numbers go through str.
  presets = {
    printer = user printerName "MyKlipper 0.4 nozzle" // {
      type = "machine";
      nozzle_diameter = [ (str machine.nozzle) ];
      min_layer_height = [ (str (machine.nozzle * 0.2)) ];
      max_layer_height = [ (str (machine.nozzle * 0.8)) ];
      printable_area = [
        "0x0"
        "${str bed.x}x0"
        "${str bed.x}x${str bed.y}"
        "0x${str bed.y}"
      ];
      printable_height = str machine.height;
      machine_max_speed_x = limit machine.velocity;
      machine_max_speed_y = limit machine.velocity;
      machine_max_speed_z = limit machine.zVelocity;
      machine_max_acceleration_x = limit machine.accel;
      machine_max_acceleration_y = limit machine.accel;
      machine_max_acceleration_z = limit machine.zAccel;
      machine_max_acceleration_extruding = limit machine.accel;
      machine_max_acceleration_retracting = limit machine.accel;
      machine_max_acceleration_travel = limit machine.accel;
      retraction_length = [ (str machine.retraction.length) ];
      retraction_speed = [ (str machine.retraction.speed) ];
      deretraction_speed = [ (str machine.retraction.speed) ];
      # Without heating commands of its own, Orca adds a full heat-up before
      # PRINT_START. These two keep the heating in the macro.
      machine_start_gcode = ''
        M140 S0
        M104 S0
        PRINT_START BED=[bed_temperature_initial_layer_single] EXTRUDER=[nozzle_temperature_initial_layer]
      '';
      machine_end_gcode = "PRINT_END";
      machine_pause_gcode = "PAUSE";
      default_filament_profile = [ filamentName ];
      default_print_profile = processName;
      host_type = "octoprint";
      print_host = url;
      print_host_webui = url;
    };

    filament = user filamentName "Generic PLA-CF @System" // {
      type = "filament";
      compatible_printers = [ printerName ];
      filament_diameter = [ (str machine.filament) ];
      nozzle_temperature = [ "230" ];
      nozzle_temperature_initial_layer = [ "230" ];
      nozzle_temperature_range_low = [ "225" ];
      nozzle_temperature_range_high = [ "245" ];
      # The vendor manual recommends 50 for PLA, on every plate type.
      cool_plate_temp = [ "50" ];
      cool_plate_temp_initial_layer = [ "50" ];
      eng_plate_temp = [ "50" ];
      eng_plate_temp_initial_layer = [ "50" ];
      hot_plate_temp = [ "50" ];
      hot_plate_temp_initial_layer = [ "50" ];
      textured_plate_temp = [ "50" ];
      textured_plate_temp_initial_layer = [ "50" ];
      filament_max_volumetric_speed = [ "8" ];
    };

    # Speeds follow the vendor manual.
    process = user processName "0.20mm Standard @MyKlipper" // {
      type = "process";
      compatible_printers = [ printerName ];
      initial_layer_print_height = str (machine.nozzle * 0.5);
      default_acceleration = str machine.accel;
      initial_layer_acceleration = "500";
      outer_wall_acceleration = "700";
      inner_wall_acceleration = str machine.accel;
      top_surface_acceleration = str machine.accel;
      travel_acceleration = str machine.accel;
      initial_layer_speed = "20";
      initial_layer_infill_speed = "30";
      outer_wall_speed = "30";
      inner_wall_speed = "45";
      sparse_infill_speed = "80";
      internal_solid_infill_speed = "60";
      top_surface_speed = "40";
      gap_infill_speed = "30";
      travel_speed = "100";
    };
  };

  files = pkgs.linkFarm "orca-presets" (
    lib.mapAttrsToList (kind: preset: {
      name = "profi3dmaker-${kind}.json";
      path = pkgs.writeText "profi3dmaker-${kind}.json" (builtins.toJSON preset);
    }) presets
  );
in
{
  services.nginx.virtualHosts.${config.services.mainsail.hostName}.locations = {
    "/orca/" = {
      alias = "${files}/";
      extraConfig = "autoindex on;";
    };
    # Orca needs the certificate to trust uploads.
    "= /orca/filamancer.pem".alias = config.services.mainsail.nginx.sslCertificate;
  };
}
