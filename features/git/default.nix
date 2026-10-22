{
  flake.modules.homeManager.git =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      git = config.programs.git.package;

      script =
        name: runtimeInputs:
        pkgs.writeShellApplication {
          inherit name runtimeInputs;
          text = builtins.readFile ./${name}.sh;
        };

      listDeadBranches = script "list-dead-branches" [
        git
        pkgs.gawk
      ];
      pruneDeadBranches = script "prune-dead-branches" [
        git
        listDeadBranches
      ];
      pullBranch = script "pull-branch" [
        git
        pkgs.coreutils
      ];
    in
    {
      programs.git = {
        enable = true;
        lfs.enable = true;

        settings = {
          alias = {
            list-dead-branches = "!${lib.getExe listDeadBranches}";
            prune-dead-branches = "!${lib.getExe pruneDeadBranches}";
            pull-branch = "!${lib.getExe pullBranch}";
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
            gpgSign = "if-asked";
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
          branch = {
            sort = "-committerdate";
            autoSetupMerge = "simple";
          };
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
