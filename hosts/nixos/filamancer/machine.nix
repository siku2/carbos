{
  nozzle = 0.5;
  filament = 1.75;

  bed = {
    x = 400;
    y = 260;
  };
  height = 190;

  velocity = 200;
  accel = 1000;
  zVelocity = 5;
  zAccel = 50;

  # The extruder drives the hotend directly. The vendor manual recommends 1 to
  # 1.5 mm.
  retraction = {
    length = 1.5;
    speed = 30;
  };

  # Klipper and Orca both take numbers as text. toString pads floats with
  # zeros, so these go.
  str =
    x:
    if builtins.isFloat x then
      builtins.head (builtins.match "([0-9]+\\.[0-9]*[1-9]|[0-9]+)\\.?0*" (toString x))
    else
      toString x;
}
