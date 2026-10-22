{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.carbos.defaultApps;

  matches =
    pattern: type:
    if lib.hasSuffix "/*" pattern then
      lib.hasPrefix (lib.removeSuffix "*" pattern) type
    else
      pattern == type;

  app =
    { name, config, ... }:
    let
      entries = config.package.desktopEntries or { };
      claimed = entries.${config.desktopEntry} or [ ];
    in
    {
      options = {
        package = mkOption {
          type = types.package;
          default = pkgs.${name};
          defaultText = lib.literalExpression "pkgs.${name}";
        };

        desktopEntry = mkOption {
          type = types.enum (lib.attrNames entries);
          default =
            let
              candidates = lib.attrNames (lib.filterAttrs (_: claims: claims != [ ]) entries);
            in
            if entries == { } then
              throw "carbos.defaultApps.${name}: declare its desktop entries in pkgs/${name}/default.nix."
            else if lib.length candidates == 1 then
              lib.head candidates
            else
              throw "carbos.defaultApps.${name}: set desktopEntry to one of ${lib.concatStringsSep ", " candidates}.";
          defaultText = "The only desktop entry that claims types.";
          description = "Desktop file ID without the .desktop suffix.";
        };

        mimeTypes = mkOption {
          type = types.listOf types.str;
          description = "Types to open, either exact or as `major/*`.";
        };

        resolved = mkOption {
          type = types.listOf types.str;
          readOnly = true;
          default = lib.filter (type: lib.any (pattern: matches pattern type) config.mimeTypes) claimed;
          description = "Claimed types that match {option}`mimeTypes`.";
        };
      };
    };

  # Fails when the desktop files no longer match the declared entries.
  check =
    package:
    pkgs.runCommand "${package.name}-desktop-entries"
      {
        expected = lib.concatLines (
          lib.concatLists (
            lib.mapAttrsToList (id: claims: [ id ] ++ map (type: "${id} ${type}") claims) package.desktopEntries
          )
        );
      }
      ''
        for file in ${package}/share/applications/*.desktop; do
          id=$(basename "$file" .desktop)
          echo "$id"
          sed -n 's/^MimeType=//p' "$file" | tr ';' '\n' | sed "/^$/d; s|^|$id |"
        done | LC_ALL=C sort -u > actual

        if ! diff -u <(printf '%s' "$expected" | LC_ALL=C sort -u) actual; then
          echo "${package.pname} no longer matches its desktopEntries"
          exit 1
        fi
        touch $out
      '';

  apps = lib.attrValues cfg;

  owners = lib.zipAttrs (
    lib.concatMap (a: map (type: { ${type} = "${a.desktopEntry}.desktop"; }) a.resolved) apps
  );
in
{
  options.carbos.defaultApps = mkOption {
    type = types.attrsOf (types.submodule app);
    default = { };
    description = "Apps that open files by default, keyed by package name.";
  };

  config = {
    assertions =
      lib.concatLists (
        lib.mapAttrsToList (
          name: a:
          map (pattern: {
            assertion = lib.any (matches pattern) (a.package.desktopEntries.${a.desktopEntry} or [ ]);
            message = "carbos.defaultApps.${name}: ${a.desktopEntry} claims no type matching ${pattern}.";
          }) a.mimeTypes
        ) cfg
      )
      ++ lib.mapAttrsToList (type: owners: {
        assertion = lib.length owners == 1;
        message = "carbos.defaultApps: ${type} is claimed by ${lib.concatStringsSep ", " owners}.";
      }) owners;

    environment.systemPackages = map (a: a.package) apps;

    xdg.mime.defaultApplications = lib.mapAttrs (_: lib.head) owners;

    system.checks = map (a: check a.package) apps;
  };
}
