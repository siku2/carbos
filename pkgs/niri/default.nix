{ niri }:
# prefer-windowed-fullscreen and open-windowed-fullscreen window rules from
# https://github.com/cwelsys/niri/commit/31416e7240d17517af34fef11ac808ff192f8c81,
# based on the unmerged YaLTeR/niri#3566 and #3687.
niri.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./windowed-fullscreen.patch ];
})
