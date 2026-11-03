{ config, lib, ... }:
lib.mkIf (config.carbos.vault.backend == "1password") {
  programs = {
    _1password.enable = true;
    _1password-gui.enable = true;
  };
}
