{ lib, ... }:
let
  workspaces = map toString (lib.range 1 9);
in
{
  services.aerospace = {
    enable = true;
    settings = {
      default-root-container-layout = "accordion";

      mode.main.binding = {
        alt-h = "focus left";
        alt-j = "focus down";
        alt-k = "focus up";
        alt-l = "focus right";

        alt-shift-h = "move left";
        alt-shift-j = "move down";
        alt-shift-k = "move up";
        alt-shift-l = "move right";

        alt-minus = "resize smart -50";
        alt-equal = "resize smart +50";

        alt-slash = "layout tiles accordion";
        alt-comma = "layout horizontal vertical";
        alt-f = "fullscreen";
        alt-shift-space = "layout floating tiling";

        alt-tab = "workspace-back-and-forth";
        alt-shift-tab = "move-workspace-to-monitor --wrap-around next";

        alt-shift-semicolon = "mode service";
      }
      // lib.genAttrs' workspaces (ws: lib.nameValuePair "alt-${ws}" "workspace ${ws}")
      // lib.genAttrs' workspaces (
        ws: lib.nameValuePair "alt-shift-${ws}" "move-node-to-workspace ${ws}"
      );

      mode.service.binding = {
        esc = [
          "reload-config"
          "mode main"
        ];
        r = [
          "flatten-workspace-tree"
          "mode main"
        ];
        backspace = [
          "close-all-windows-but-current"
          "mode main"
        ];
      };

      on-window-detected = [
        {
          "if".app-id = "dev.zed.Zed";
          run = "move-node-to-workspace 1";
        }
        {
          "if".app-id = "org.mozilla.firefox";
          run = "move-node-to-workspace 2";
        }
        {
          "if".app-id = "com.microsoft.teams2";
          run = "move-node-to-workspace 3";
        }
        {
          "if".app-id = "com.1password.1password";
          run = "layout floating";
        }
        {
          "if".app-id = "com.apple.systempreferences";
          run = "layout floating";
        }
      ];
    };
  };

  system.defaults = {
    # Recommended by AeroSpace.
    dock.expose-group-apps = true;
    spaces.spans-displays = true;

    # Built-in window management that would fight AeroSpace.
    WindowManager = {
      GloballyEnabled = false;
      EnableTilingByEdgeDrag = false;
      EnableTopTilingByEdgeDrag = false;
      EnableTilingOptionAccelerator = false;
    };
  };
}
