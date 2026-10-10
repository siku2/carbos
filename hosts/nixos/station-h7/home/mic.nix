{
  carbos.mic = {
    enable = true;
    name = "RØDE Procaster";
    device = "alsa_input.usb-Solid_State_Logic_SSL_2_Mk_II-00.HiFi__Mic1__source";

    plugins = [
      # Highway and fan rumble.
      {
        filter = {
          type = "Hi-pass";
          slope = "x2";
          frequency = 100.0;
          gain = 0.0;
          quality = 0.0;
        };
      }
      # Broad PC fan hum at 170-225 Hz. Q 4 spares the voice fundamental around 100 Hz.
      {
        filter = {
          type = "Bell";
          slope = "x1";
          frequency = 195.0;
          gain = -6.0;
          quality = 4.0;
        };
      }
      {
        deepfilternet = {
          attenuation-limit = 25.0;
          min-processing-threshold = -15.0;
          max-erb-processing-threshold = 30.0;
          max-df-processing-threshold = 20.0;
        };
      }
      # Full gate. -72 dB is the LSP maximum and silences what DeepFilterNet leaves of the room.
      # The raw room sits at -55 dBFS and the quietest speech at about -42.
      {
        gate = {
          attack = 2.0;
          release = 200.0;
          curve-threshold = -52.0;
          curve-zone = -6.0;
          hysteresis = true;
          hysteresis-threshold = -3.0;
          hysteresis-zone = -3.0;
          reduction = -72.0;
          sidechain = {
            mode = "RMS";
            lookahead = 5.0;
            reactivity = 10.0;
          };
        };
      }
      {
        limiter = {
          threshold = -1.0;
          attack = 5.0;
          release = 5.0;
          lookahead = 5.0;
          alr = false;
          gain-boost = false;
        };
      }
    ];
  };
}
