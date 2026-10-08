{
  flake.modules.homeManager.git =
    { config, ... }:
    {
      imports = [ ./_options.nix ];

      programs.git = {
        enable = true;
        lfs.enable = true;

        settings = {
          alias = {
            list-dead-branches = "!git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads | awk '$2 == \"[gone]\" {print $1}'";
            prune-dead-branches = "!f() { git fetch --prune && git list-dead-branches | while read branch; do git branch -D \"$branch\"; done; }; f";
          };

          user = {
            name = config.carbos.user.fullName;
            email = config.carbos.user.email;
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
            forceSignAnnotated = true;
            sort = "version:refname";
          };
          branch.sort = "-committerdate";
          status.showUntrackedFiles = "all";
          column.ui = "auto";
          help.autocorrect = "prompt";
        };

        ignores = [
          "/.claude/"
          "/.direnv/"
          "/scratch/"
        ];
      };
    };
}
