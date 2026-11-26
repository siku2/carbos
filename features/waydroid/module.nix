{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.carbos.waydroid = {
    user = mkOption {
      type = types.str;
      default = config.carbos.user.login;
      defaultText = lib.literalExpression "config.carbos.user.login";
      description = "User whose session runs Android on tty1.";
    };

    overlays = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "com.android.internal.systemui.navbar.gestural" ];
      description = "Android overlays to enable. Each one disables the others in its category.";
    };

    apps = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = ''
        APKs to install, each with `packageName` and `versionCode` in
        passthru. An app is installed when it is missing or older than the
        pinned version. Newer versions are left alone.
      '';
    };
  };
}
