{
  osConfig,
  pkgs,
  ...
}:
let
  # Held by Bitwarden's SSH agent, never on disk.
  signingKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJc/x0F5XV2bnqHZFHZUlPmY/D24+mxhAWOR8D5LjyVi";

  allowedSigners = pkgs.writeText "git-allowed-signers" ''
    ${osConfig.carbos.user.email} namespaces="git" ${signingKey}
  '';
in
{
  programs.git = {
    enable = true;

    settings = {
      alias = {
        ls-dead-branches = "!git fetch --prune && git for-each-ref --format '%(refname:short) %(upstream:track)' | awk '$2 == \"[gone]\" {print $1}'";
        prune-dead-branches = "!git ls-dead-branches | xargs -r git branch -D";
      };

      user = {
        name = osConfig.carbos.user.fullName;
        email = osConfig.carbos.user.email;
        signingkey = "key::${signingKey}";
      };
      init.defaultBranch = "main";
      pull.ff = "only";
      commit.gpgsign = true;
      tag.gpgsign = true;
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
      "/.claude/"
      "/.direnv/"
      "/AGENTS.md"
      "/opencode.json"
      "/scratch/"
    ];
  };
}
