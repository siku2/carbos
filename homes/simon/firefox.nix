{
  config,
  lib,
  pkgs,
  ...
}:
let
  # DMS already launches apps in a transient scope named after their pid, so an
  # explicit unit name is needed here or the two collide and the launch fails.
  firefoxInSlice = pkgs.writeShellScriptBin "firefox" ''
    exec ${pkgs.systemd}/bin/systemd-run --user --scope --quiet --collect \
      --unit="firefox-$$" --slice=firefox.slice \
      ${lib.getExe config.programs.firefox.finalPackage} "$@"
  '';

  firefox = lib.getExe firefoxInSlice;

  bitwardenId = "{446900e4-71c2-419f-a6a7-df9c091e268b}";

  fromAmo = slug: {
    install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
    installation_mode = "normal_installed";
  };

  # Collapses while a window holds one tab and returns as soon as there is a
  # second, so a stray tab can never end up unreachable.
  tabBarCss = pkgs.writeText "tab-bar.css" ''
    @-moz-document url("chrome://browser/content/browser.xhtml") {
      #TabsToolbar:has(#tabbrowser-arrowscrollbox > tab:only-of-type) {
        visibility: collapse !important;
      }
    }
  '';
in
{
  programs.firefox = {
    enable = true;

    # Registering the sheet from autoconfig keeps it out of the profile, which
    # is the only writable place userChrome.css can live.
    package = pkgs.firefox.override {
      extraPrefs = ''
        try {
          var sss = Components.classes["@mozilla.org/content/style-sheet-service;1"]
            .getService(Components.interfaces.nsIStyleSheetService);
          sss.loadAndRegisterSheet(Services.io.newURI("file://${tabBarCss}"), sss.USER_SHEET);
        } catch (e) {
          Components.utils.reportError(e);
        }

        // There is no pref for key bindings. Catching the event in the capture
        // phase beats the <key> element to it.
        try {
          Services.obs.addObserver(function (win) {
            win.addEventListener("keydown", function (e) {
              if (e.ctrlKey && !e.shiftKey && !e.altKey && !e.metaKey && e.key === "t") {
                e.preventDefault();
                e.stopPropagation();
                win.OpenBrowserWindow();
              }
            }, true);
          }, "browser-delayed-startup-finished");
        } catch (e) {
          Components.utils.reportError(e);
        }
      '';
    };

    policies = {
      ExtensionSettings = {
        ${bitwardenId} = fromAmo "bitwarden-password-manager";
        "{5caff8cc-3d2e-4110-a88a-003cc85b3858}" = fromAmo "vue-js-devtools";
        "{a293603d-51d6-40f3-8d85-26d2c9610ae2}" = fromAmo "vue-force-dev";
        "addon@darkreader.org" = fromAmo "darkreader";
        "gsconnect@andyholmes.github.io" = fromAmo "gsconnect";
        "@react-devtools" = fromAmo "react-devtools";
        "sponsorBlocker@ajay.app" = fromAmo "sponsorblock";
        "svg-screenshots@felixfbecker" = fromAmo "svg-screenshots";
        "@ublacklist" = fromAmo "ublacklist";
        "uBlock0@raymondhill.net" = fromAmo "ublock-origin";
      };

      "3rdparty".Extensions.${bitwardenId}.environment = {
        base = "https://vault.bg12.ch";
      };

      # Names as they ship for en-US in region CH.
      SearchEngines = {
        Default = "DuckDuckGo";
        Remove = [
          "Bing"
          "Ecosia"
          "Perplexity"
          "Qwant"
          "Reddit"
          "Startpage"
          "Wikipedia (en)"
          "YouTube"
          "eBay"
        ];
      };

      DisplayBookmarksToolbar = "never";

      DisableAppUpdate = true;
      ExtensionUpdate = true;

      Preferences = {
        # Links that would have opened a tab open a window instead. Popups with
        # window features are unaffected by open_newwindow.restriction = 2.
        "browser.link.open_newwindow" = {
          Value = 2;
          Status = "default";
        };
        "dom.ipc.processCount" = {
          Value = 4;
          Status = "default";
        };
        "browser.tabs.unloadOnLowMemory" = {
          Value = true;
          Status = "default";
        };
        "browser.sessionhistory.max_total_viewers" = {
          Value = 2;
          Status = "default";
        };
        "browser.newtabpage.activity-stream.showWeather" = {
          Value = false;
          Status = "default";
        };
      };

      FirefoxHome = {
        SponsoredTopSites = false;
        SponsoredPocket = false;
        SponsoredStories = false;
        Locked = false;
      };
      FirefoxSuggest.SponsoredSuggestions = false;

      PasswordManagerEnabled = false;

      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisableTelemetry = true;

      DontCheckDefaultBrowser = true;
      NoDefaultBookmarks = true;
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";

      DNSOverHTTPS = {
        Enabled = true;
        Locked = false;
      };
    };
  };

  systemd.user.slices.firefox = {
    Unit.Description = "Firefox";
    Slice.MemoryHigh = "8G";
  };

  # xdg.enable is off, so xdg.desktopEntries would be dropped silently.
  home.file.".local/share/applications/firefox.desktop".source =
    let
      item = pkgs.makeDesktopItem {
        name = "firefox";
        desktopName = "Firefox";
        genericName = "Web Browser";
        icon = "firefox";
        exec = "${firefox} --name firefox %U";
        categories = [
          "Network"
          "WebBrowser"
        ];
        mimeTypes = [
          "text/html"
          "text/xml"
          "application/xhtml+xml"
          "application/vnd.mozilla.xul+xml"
          "x-scheme-handler/http"
          "x-scheme-handler/https"
        ];
        startupNotify = true;
        startupWMClass = "firefox";
        actions = {
          new-private-window = {
            name = "New Private Window";
            exec = "${firefox} --private-window %U";
          };
          new-window = {
            name = "New Window";
            exec = "${firefox} --new-window %U";
          };
          profile-manager-window = {
            name = "Profile Manager";
            exec = "${firefox} --ProfileManager";
          };
        };
      };
    in
    "${item}/share/applications/firefox.desktop";
}
