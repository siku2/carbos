{
  lib,
  ...
}:
{
  xdg.configFile."niri/config.kdl".text = ''
    config-notification {
        disable-failed
    }

    gestures {
        hot-corners {
            off
        }
    }

    input {
        keyboard {
            xkb {
            }
            numlock
        }

        trackpoint {
        }
    }

    layout {
        background-color "transparent"
        center-focused-column "never"
        preset-column-widths {
            proportion 0.33333
            proportion 0.5
            proportion 0.66667
        }
        default-column-width { proportion 0.5; }
        border {
            off
            width 4
        }
        shadow {
            softness 30
            spread 5
            offset x=0 y=5
            color "#0007"
        }
        struts {
        }
    }

    layer-rule {
        match namespace="^quickshell$"
        place-within-backdrop true
    }

    overview {
        workspace-shadow {
            off
        }
    }

    environment {
        XDG_CURRENT_DESKTOP "niri"
    }

    hotkey-overlay {
        skip-at-startup
    }

    prefer-no-csd

    screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"

    animations {
        workspace-switch {
            spring damping-ratio=0.80 stiffness=523 epsilon=0.0001
        }
        window-open {
            duration-ms 150
            curve "ease-out-expo"
        }
        window-close {
            duration-ms 150
            curve "ease-out-quad"
        }
        horizontal-view-movement {
            spring damping-ratio=0.85 stiffness=423 epsilon=0.0001
        }
        window-movement {
            spring damping-ratio=0.75 stiffness=323 epsilon=0.0001
        }
        window-resize {
            spring damping-ratio=0.85 stiffness=423 epsilon=0.0001
        }
        config-notification-open-close {
            spring damping-ratio=0.65 stiffness=923 epsilon=0.001
        }
        screenshot-ui-open {
            duration-ms 200
            curve "ease-out-quad"
        }
        overview-open-close {
            spring damping-ratio=0.85 stiffness=800 epsilon=0.0001
        }
    }

    window-rule {
        match app-id=r#"^org\.wezfurlong\.wezterm$"#
        default-column-width {}
    }

    window-rule {
        match app-id=r#"^org\.gnome\."#
        draw-border-with-background false
        geometry-corner-radius 12
        clip-to-geometry true
    }

    window-rule {
        match app-id=r#"^gnome-control-center$"#
        match app-id=r#"^pavucontrol$"#
        match app-id=r#"^nm-connection-editor$"#
        default-column-width { proportion 0.5; }
        open-floating false
    }

    window-rule {
        match app-id=r#"^org\.gnome\.Calculator$"#
        match app-id=r#"^gnome-calculator$"#
        match app-id=r#"^galculator$"#
        match app-id=r#"^blueman-manager$"#
        match app-id=r#"^org\.gnome\.Nautilus$"#
        match app-id=r#"^xdg-desktop-portal$"#
        open-floating true
    }

    window-rule {
        match app-id=r#"^steam$"# title=r#"^notificationtoasts_\d+_desktop$"#
        default-floating-position x=10 y=10 relative-to="bottom-right"
        open-focused false
    }

    window-rule {
        match app-id=r#"^org\.wezfurlong\.wezterm$"#
        match app-id="Alacritty"
        match app-id="zen"
        match app-id="com.mitchellh.ghostty"
        match app-id="kitty"
        match app-id="foot"
        draw-border-with-background false
    }

    window-rule {
        match app-id=r#"firefox$"# title="^Picture-in-Picture$"
        match app-id="zoom"
        open-floating true
    }

    debug {
        honor-xdg-activation-with-invalid-serial
    }

    recent-windows {
        binds {
            Alt+Tab         { next-window scope="output"; }
            Alt+Shift+Tab   { previous-window scope="output"; }
            Alt+grave       { next-window filter="app-id"; }
            Alt+Shift+grave { previous-window filter="app-id"; }
        }
    }

    include optional=true "dms/colors.kdl"
    include optional=true "dms/layout.kdl"
    include optional=true "dms/alttab.kdl"
    include optional=true "dms/binds.kdl"
    include optional=true "dms/outputs.kdl"
    include optional=true "dms/cursor.kdl"
    include optional=true "dms/input.kdl"
    include optional=true "dms/windowrules.kdl"
  '';

  home.activation.dmsNiriFragments = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dms_dir="$HOME/.config/niri/dms"
    mkdir -p "$dms_dir"
    for f in ${./files/niri-dms}/*.kdl; do
        name=$(basename "$f")
        if [ ! -e "$dms_dir/$name" ]; then
            # DMS rewrites these itself, so they must not keep the store's mode.
            install -m 644 "$f" "$dms_dir/$name"
        fi
    done
  '';
}
