{
  carbos.registry = {
    hosts = {
      carbon-x1.builder = {
        key = "carbon-x1-builder";
        machines = [ "station-h7" ];
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
      };
      carbon-x1-builder = {
        algorithm = "ssh-ed25519";
        key = "AAAAC3NzaC1lZDI1NTE5AAAAIEb6hqkUuL+eDx7sTkBSoTbN4/iZ0+PIOnlyYdldiHn5";
        comment = "carbon-x1 builder";
      };
    };
  };
}
