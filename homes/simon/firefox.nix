_:
let
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
}
