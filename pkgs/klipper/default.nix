{ applyPatches, klipper }:
# klipper-firmware builds from klipper.src, so the patch goes into the source.
klipper.overrideAttrs (old: {
  src = applyPatches {
    # sourceRoot points into the source by its store name.
    inherit (old.src) name;
    inherit (old) src;
    patches = [ ./atmega1281.patch ];
  };
})
