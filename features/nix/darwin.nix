{
  nix = {
    gc = {
      automatic = true;
      interval = [
        {
          Weekday = 1;
          Hour = 12;
          Minute = 30;
        }
      ];
      options = "--delete-older-than 14d";
    };

    optimise = {
      automatic = true;
      # After the GC run above, so it scans fewer paths.
      interval = [
        {
          Weekday = 1;
          Hour = 13;
          Minute = 30;
        }
      ];
    };
  };
}
