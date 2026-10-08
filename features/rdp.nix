{
  flake.modules.homeManager.rdp =
    { config, lib, ... }:
    let
      cfg = config.rdp;

      # .rdp settings are "name:type:value", where type is i (integer) or s (string).
      toRdp =
        settings:
        lib.concatStrings (
          lib.mapAttrsToList (
            name: value:
            if lib.isBool value then
              "${name}:i:${if value then "1" else "0"}\r\n"
            else if lib.isInt value then
              "${name}:i:${toString value}\r\n"
            else
              "${name}:s:${value}\r\n"
          ) settings
        );
    in
    {
      options.rdp = {
        directory = lib.mkOption {
          type = lib.types.str;
          default = "RDP";
          description = "Directory relative to the home directory that holds the generated .rdp files.";
        };

        connections = lib.mkOption {
          type =
            with lib.types;
            attrsOf (
              attrsOf (oneOf [
                bool
                int
                str
              ])
            );
          default = { };
          example = {
            build-server = {
              "full address" = "build.example.com";
              username = "EXAMPLE\\simon";
              "use multimon" = true;
            };
          };
          description = ''
            RDP connections, one .rdp file per attribute. Keys are .rdp setting
            names. Booleans and integers are written as type i, strings as type s.
          '';
        };
      };

      config.home.file = lib.mapAttrs' (
        name: settings: lib.nameValuePair "${cfg.directory}/${name}.rdp" { text = toRdp settings; }
      ) cfg.connections;
    };
}
