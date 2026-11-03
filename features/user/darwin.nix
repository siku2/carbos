{ config, ... }:
let
  inherit (config.carbos.user) login;
in
{
  users.users.${login}.home = "/Users/${login}";

  system.primaryUser = login;
}
