{
  # The macOS default LC_CTYPE is just "UTF-8".
  programs.ssh.settings."*" = {
    SendEnv = "LC_CTYPE";
    SetEnv.LC_CTYPE = "en_US.UTF-8";
  };
}
