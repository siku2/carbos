{
  programs.git = {
    settings.credential.helper = "osxkeychain";

    ignores = [ ".DS_Store" ];
  };
}
