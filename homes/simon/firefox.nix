{
  config,
  lib,
  pkgs,
  ...
}:
let
  runInSlice = "${pkgs.systemd}/bin/systemd-run --user --scope --quiet --slice=firefox.slice ${lib.getExe config.programs.firefox.finalPackage}";

  bitwardenId = "{446900e4-71c2-419f-a6a7-df9c091e268b}";

  fromAmo = slug: {
    install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
    installation_mode = "normal_installed";
  };
in
{
  programs.firefox = {
    enable = true;

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

      # The Bitwarden extension reads chrome.storage.managed on first install
      # and points itself at our server, so a fresh profile skips the
      # "self-host URL" step. It cannot pre-fill credentials, so the first
      # login is still done by hand.
      "3rdparty".Extensions.${bitwardenId}.environment = {
        base = "https://vault.bg12.ch";
      };

      # nix owns the package, so Firefox must never update itself. Extension
      # updates stay on, which is the whole point of installing from AMO.
      DisableAppUpdate = true;
      ExtensionUpdate = true;

      # Firefox's footprint is mostly content processes, and it never sheds
      # tabs on its own because unloadOnLowMemory is off by default.
      # Status "default" so these stay tunable in about:config.
      Preferences = {
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
      };

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

  # xdg.enable is off, so xdg.desktopEntries would be silently dropped.
  # Shadow the package's entry by hand instead.
  home.file.".local/share/applications/firefox.desktop".source =
    let
      item = pkgs.makeDesktopItem {
        name = "firefox";
        desktopName = "Firefox";
        genericName = "Web Browser";
        icon = "firefox";
        exec = "${runInSlice} --name firefox %U";
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
            exec = "${runInSlice} --private-window %U";
          };
          new-window = {
            name = "New Window";
            exec = "${runInSlice} --new-window %U";
          };
          profile-manager-window = {
            name = "Profile Manager";
            exec = "${runInSlice} --ProfileManager";
          };
        };
      };
    in
    "${item}/share/applications/firefox.desktop";
}
