{ config, ... }:
{
  # rbw-agent runs as a systemd user service.
  assertions = [
    {
      assertion = config.carbos.vault.backend != "bitwarden";
      message = "carbos.vault.backend = \"bitwarden\" only works on NixOS.";
    }
  ];
}
