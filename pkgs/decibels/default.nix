{ decibels }:
decibels.overrideAttrs (old: {
  passthru = old.passthru or { } // {
    desktopEntries = {
      "org.gnome.Decibels" = [
        "audio/mpeg"
        "audio/wav"
        "audio/x-aac"
        "audio/x-aiff"
        "audio/x-ape"
        "audio/x-flac"
        "audio/x-m4a"
        "audio/x-m4b"
        "audio/x-mp1"
        "audio/x-mp2"
        "audio/x-mp3"
        "audio/x-mpg"
        "audio/x-mpeg"
        "audio/x-mpegurl"
        "audio/x-opus+ogg"
        "audio/x-pn-aiff"
        "audio/x-pn-au"
        "audio/x-pn-wav"
        "audio/x-speex"
        "audio/x-vorbis"
        "audio/x-vorbis+ogg"
        "audio/x-wavpack"
      ];
    };
  };
})
