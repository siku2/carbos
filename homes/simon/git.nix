{ osConfig, pkgs, ... }:
let
  # Held by Bitwarden's SSH agent, never on disk.
  signingKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJc/x0F5XV2bnqHZFHZUlPmY/D24+mxhAWOR8D5LjyVi";

  allowedSigners = pkgs.writeText "git-allowed-signers" ''
    ${osConfig.carbos.user.email} namespaces="git" ${signingKey}
  '';
in
{
  programs.git = {
    settings = {
      user.signingkey = "key::${signingKey}";
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = "${allowedSigners}";
      credential = {
        helper = "manager";
        credentialstore = "secretservice";
        "https://forge.stargrid.systems".provider = "generic";
        "https://github.com".helper = [
          ""
          "!gh auth git-credential"
        ];
      };
    };

    ignores = [
      "/AGENTS.md"
      "/opencode.json"
    ];
  };
}
