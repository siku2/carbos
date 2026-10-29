{
  lib,
  fetchpatch,
  unstable,
}:
let
  # Tree row drag and drop trips the strcpy overflow check on Darwin. Fixed on
  # gtk-3-24 but not in a release yet.
  gtk3 = unstable.gtk3.overrideAttrs (old: {
    patches = old.patches or [ ] ++ [
      (fetchpatch {
        url = "https://gitlab.gnome.org/GNOME/gtk/-/commit/234b385a476b50cea34fa70896b4be10a1de32da.patch";
        hash = "sha256-FTyXMGD/kG1TRvReurwe/BPmNEQN7PxdmvOKTg1diMM=";
      })
    ];
  });
in
# Unstable has the librsvg pixbuf loader fix for Darwin.
(unstable.inkscape.override {
  gtkmm3 = unstable.gtkmm3.override { inherit gtk3; };
  gtksourceview4 = unstable.gtksourceview4.override { inherit gtk3; };
  gtk-mac-integration = unstable.gtk-mac-integration.override { inherit gtk3; };
}).overrideAttrs
  (old: {
    meta = old.meta // {
      platforms = lib.platforms.darwin;
    };
  })
