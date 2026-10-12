{ lib, ... }:
{
  services.tailscale.enable = true;

  environment.etc = lib.genAttrs' [
    "b-on.com"
    "inomo.tech"
  ] (domain: lib.nameValuePair "resolver/${domain}" { text = "nameserver 100.100.100.100"; });
}
