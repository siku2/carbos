{
  osConfig,
  ...
}:
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
        signingkey = "~/.ssh/id_ed25519.pub";
      };
      init.defaultBranch = "main";
      commit.gpgsign = true;
      tag.gpgsign = true;
      gpg.format = "ssh";
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
