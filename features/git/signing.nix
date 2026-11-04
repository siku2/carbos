{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.carbos.user.signing;

  allowedSigners = pkgs.writeText "git-allowed-signers" ''
    ${config.carbos.user.email} namespaces="git" ${cfg.key}
  '';
in
lib.mkIf (cfg != null) (
  lib.mkMerge [
    {
      programs.git.settings = {
        commit.gpgsign = true;
        tag.forceSignAnnotated = true;
      };
    }

    (lib.mkIf (cfg.format == "ssh") {
      programs.git.settings = {
        user.signingKey = "key::${cfg.key}";
        gpg.format = "ssh";
        gpg.ssh.allowedSignersFile = "${allowedSigners}";
      };
    })

    (lib.mkIf (cfg.format == "openpgp") {
      programs.git.settings.user.signingKey = cfg.key;

      programs.gpg.enable = true;

      services.gpg-agent = {
        enable = true;
        pinentry.package =
          if pkgs.stdenv.hostPlatform.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-qt;
        defaultCacheTtl = 600;
        maxCacheTtl = 7200;
      };
    })
  ]
)
