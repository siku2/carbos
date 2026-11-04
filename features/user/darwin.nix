{ config, ... }:
let
  inherit (config.carbos.user) login;
in
{
  # nix-darwin only applies users.users settings like the shell to known users.
  users.knownUsers = [ login ];

  users.users.${login} = {
    uid = 501;
    home = "/Users/${login}";
  };

  system.primaryUser = login;
}
