{
  carbos.registry = {
    hosts = {
      carbon-x1.builder = {
        key = "carbon-x1-builder";
        machines = [ "station-h7" ];
      };
      mindaro = { };
      station-h7 = {
        hostKey = "station-h7-host";
        buildMachine = {
          maxJobs = 8;
          speedFactor = 4;
        };
      };
    };

    sshKeys = {
      carbon-x1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJc/x0F5XV2bnqHZFHZUlPmY/D24+mxhAWOR8D5LjyVi carbon-x1";
      carbon-x1-builder = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEb6hqkUuL+eDx7sTkBSoTbN4/iZ0+PIOnlyYdldiHn5 carbon-x1 builder";
      station-h7-host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMpPLhVnDKIb9YHHADrC8jscDpVAKXRhFaS0ZweFR8KU root@station-h7";
    };
  };
}
