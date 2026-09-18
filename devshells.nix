{ lib, pkgs }:
let
  presets = {
    rust = import ./devshells/rust.nix { inherit pkgs; };
  };

  combinations = lib.filter (names: names != [ ]) (
    lib.foldl' (acc: name: acc ++ map (names: names ++ [ name ]) acc) [ [ ] ] (lib.attrNames presets)
  );

  mkPresetShell =
    names:
    pkgs.mkShell {
      name = lib.concatStringsSep "+" names;
      packages = lib.concatMap (name: presets.${name}.packages or [ ]) names;
      buildInputs = lib.concatMap (name: presets.${name}.buildInputs or [ ]) names;
      env = lib.foldl' (acc: name: acc // (presets.${name}.env or { })) { } names;
      shellHook = lib.concatMapStrings (name: presets.${name}.shellHook or "") names;
    };
in
lib.listToAttrs (
  map (names: lib.nameValuePair (lib.concatStringsSep "+" names) (mkPresetShell names)) combinations
)
