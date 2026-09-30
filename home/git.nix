{
  programs.git = {
    enable = true;
    lfs.enable = true;
    ignores = [
      ".DS_Store"
      ".claude/"
      ".direnv/"
      "scratch/"
    ];
    settings = {
      user = {
        name = "Simon Berger";
        email = "simon.berger@inomotech.com";
        signingKey = "BAA343801A190591C8667BDFDA52A1F326E417A2";
      };
      commit.gpgSign = true;
      tag = {
        gpgSign = true;
        forceSignAnnotated = true;
      };
      push.gpgSign = "if-asked";
      credential.helper = "osxkeychain";
      init.defaultBranch = "main";
      rerere.enabled = true;
      alias = {
        list-dead-branches = "!git branch -vv | awk '/: gone]/{print $1}'";
        prune-dead-branches = "!f() { git fetch --prune && git list-dead-branches | while read branch; do git branch -D \"$branch\"; done; }; f";
      };
    };
  };
}
