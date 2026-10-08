{
  programs.git = {
    settings = {
      user.signingKey = "BAA343801A190591C8667BDFDA52A1F326E417A2";
      credential.helper = "osxkeychain";
    };

    ignores = [ ".DS_Store" ];
  };
}
