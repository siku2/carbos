{ lib, ... }:
{
  options.carbos.vault.backend = lib.mkOption {
    type = lib.types.enum [
      "bitwarden"
      "1password"
    ];
    default = "bitwarden";
    description = "Password manager of this host.";
  };
}
