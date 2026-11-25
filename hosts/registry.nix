{ config, lib, ... }:
let
  allHosts = lib.attrNames config.carbos.registry.hosts;
in
{
  carbos.registry = {
    hosts = {
      carbon-x1.builder = {
        key = "carbon-x1-builder";
        machines = [ "station-h7" ];
      };
      filamancer.hostKey = {
        algorithm = "ssh-ed25519";
        key = "AAAAC3NzaC1lZDI1NTE5AAAAIEy4wnM1zT0ceHibgs716kFUhLHzHTFrUM0du/0ZMpzg";
        comment = "root@filamancer";
      };
      fizzy.hostKey = {
        algorithm = "ssh-ed25519";
        key = "AAAAC3NzaC1lZDI1NTE5AAAAILPvWIIUVf/kbop/ntjc5D4ndEzc9JrFwaNevTV0UsoU";
        comment = "root@fizzy";
      };
      mindaro = { };
      station-h7 = {
        hostKey = {
          algorithm = "ssh-ed25519";
          key = "AAAAC3NzaC1lZDI1NTE5AAAAIMpPLhVnDKIb9YHHADrC8jscDpVAKXRhFaS0ZweFR8KU";
          comment = "root@station-h7";
        };
        buildMachine = {
          maxJobs = 8;
          speedFactor = 4;
        };
      };
    };

    sshKeys = {
      carbon-x1 = {
        algorithm = "ssh-ed25519";
        key = "AAAAC3NzaC1lZDI1NTE5AAAAIJc/x0F5XV2bnqHZFHZUlPmY/D24+mxhAWOR8D5LjyVi";
        comment = "carbon-x1";
        vaultEntry = "carbon-x1";
        login = allHosts;
      };
      carbon-x1-builder = {
        algorithm = "ssh-ed25519";
        key = "AAAAC3NzaC1lZDI1NTE5AAAAIEb6hqkUuL+eDx7sTkBSoTbN4/iZ0+PIOnlyYdldiHn5";
        comment = "carbon-x1 builder";
      };
      itma-23001 = {
        algorithm = "ssh-ed25519";
        key = "AAAAC3NzaC1lZDI1NTE5AAAAIOYh6Y9KHLXpqgTbTjsy9ajqwVlZ+Tfc+0Cn/w/JiAK9";
        comment = "itma-23001";
        login = allHosts;
      };
    };
  };
}
