{ lib, ... }:
let
  machine = import ./machine.nix;
  inherit (machine) str;

  # A 100 mm purge line, 0.6 nozzle widths high and 1.2 wide.
  purge = rec {
    height = 0.6 * machine.nozzle;
    filamentArea = 3.14159 * machine.filament * machine.filament / 4;
    extrude = height * 1.2 * machine.nozzle * 100 / filamentArea;
  };

  # The klipper module writes each list item as an indented line.
  lines = text: lib.filter (line: line != "") (lib.splitString "\n" text);

  # Moves the nozzle 10 mm up without passing the top of the axis.
  liftZ = ''
    {% set th = printer.toolhead %}
    G90
    G1 Z{[th.position.z + 10, th.axis_maximum.z]|min} F600
  '';

  retract = ''
    {% if printer.extruder.can_extrude %}
    M83
    G1 E-2 F1800
    {% endif %}
  '';
in
{
  services.klipper.settings = {
    "gcode_macro PRINT_START" = {
      description = "Home, heat and purge. Use PRINT_START BED=60 EXTRUDER=210";
      gcode = lines ''
        {% set bed = params.BED|default(60)|float %}
        {% set extruder = params.EXTRUDER|default(210)|float %}
        M140 S{bed}
        M104 S150
        G90
        G28
        G1 Z10 F600
        M190 S{bed}
        M109 S{extruder}
        M83
        G1 X10 Y5 F6000
        G1 Z${str purge.height} F600
        G1 X110 E${str purge.extrude} F600
        G1 Z2 F600
      '';
    };

    "gcode_macro PRINT_END" = {
      description = "Retract, lift and turn everything off";
      gcode = lines ''
        M400
        ${retract}
        ${liftZ}
        TURN_OFF_HEATERS
        M106 S0
        M84
      '';
    };

    "gcode_macro CANCEL_PRINT" = {
      description = "Cancel the print and turn everything off";
      rename_existing = "CANCEL_PRINT_BASE";
      gcode = lines ''
        PRINT_END
        CLEAR_PAUSE
        CANCEL_PRINT_BASE
      '';
    };

    "gcode_macro PAUSE" = {
      description = "Pause the print and lift the nozzle";
      rename_existing = "PAUSE_BASE";
      gcode = lines ''
        PAUSE_BASE
        SET_GCODE_VARIABLE MACRO=RESUME VARIABLE=retracted VALUE={printer.extruder.can_extrude|int}
        ${retract}
        ${liftZ}
      '';
    };

    "gcode_macro RESUME" = {
      description = "Resume the print where it was paused";
      rename_existing = "RESUME_BASE";
      variable_retracted = 0;
      gcode = lines ''
        {% if retracted %}
        M83
        G1 E2 F1800
        SET_GCODE_VARIABLE MACRO=RESUME VARIABLE=retracted VALUE=0
        {% endif %}
        RESUME_BASE
      '';
    };
  };
}
