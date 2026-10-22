{
  config,
  lib,
  pkgs,
  ...
}:
let
  dir = lib.escapeShellArg "${config.xdg.dataHome}/keyrings";

  keyring = pkgs.writeText "Default.keyring" ''
    [keyring]
    display-name=Default
    ctime=0
    mtime=0
    lock-on-idle=false
    lock-after=false
  '';

  pointer = pkgs.writeText "default" "Default\n";
in
{
  # Seed an unencrypted default.
  home.activation.defaultKeyring = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e ${dir}/default ]; then
      run mkdir -p -m 700 ${dir}
      run install -m 600 ${keyring} ${dir}/Default.keyring
      run install -m 644 ${pointer} ${dir}/default
    fi
  '';
}
