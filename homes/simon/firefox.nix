{
  config,
  lib,
  pkgs,
  ...
}:
let
  # DMS already launches every app in a transient scope named after its pid, so
  # the inner scope needs an explicit unit name or it collides and the launch
  # fails.
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

      # Read from chrome.storage.managed on first install, so a fresh profile
      # skips the self-host URL step.
      "3rdparty".Extensions.${bitwardenId}.environment = {
        base = "https://vault.bg12.ch";
      };

      DisableAppUpdate = true;
      ExtensionUpdate = true;

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
