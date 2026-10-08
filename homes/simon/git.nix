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
        list-dead-branches = "!git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads | awk '$2 == \"[gone]\" {print $1}'";
        prune-dead-branches = "!f() { git fetch --prune && git list-dead-branches | while read branch; do git branch -D \"$branch\"; done; }; f";
      };

      user = {
        name = osConfig.carbos.user.fullName;
        email = osConfig.carbos.user.email;
        signingkey = "key::${signingKey}";
      };
      init.defaultBranch = "main";
      pull.ff = "only";
      fetch.prune = true;
      push = {
        autoSetupRemote = true;
        useForceIfIncludes = true;
      };
      rebase = {
        autoStash = true;
        autoSquash = true;
        missingCommitsCheck = "error";
        updateRefs = true;
      };
      rerere.enabled = true;
      merge.conflictStyle = "zdiff3";
      diff = {
        algorithm = "histogram";
        colorMoved = "default";
        mnemonicPrefix = true;
      };
      commit = {
        gpgsign = true;
        verbose = true;
      };
      tag = {
        gpgsign = true;
        sort = "version:refname";
      };
      branch.sort = "-committerdate";
      status.showUntrackedFiles = "all";
      column.ui = "auto";
      help.autocorrect = "prompt";
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
