{ config, lib, ... }:
let
  inherit (config.carbos.registry) hosts;
  inherit (config.networking) hostName;

  self = hosts.${hostName};
  machines = map (name: hosts.${name}) self.builder.machines;
  clients = lib.filterAttrs (
    _: host: host.builder != null && lib.elem hostName host.builder.machines
  ) hosts;
in
lib.mkMerge [
  (lib.mkIf (self.buildMachine != null) {
    nix.sshServe = {
      enable = true;
      protocol = "ssh-ng";
      write = true;
      # The paths clients send are unsigned.
      trusted = true;
      keys = lib.mapAttrsToList (_: host: host.builder.key.line) clients;
    };
  })

  (lib.mkIf (self.builder != null) {
    assertions = lib.zipListsWith (name: host: {
      assertion = host.buildMachine != null;
      message = "${hostName} builds on ${name}, which has no buildMachine.";
    }) self.builder.machines machines;

    nix = {
      distributedBuilds = true;
      buildMachines = map (host: {
        hostName = host.fqdn;
        protocol = "ssh-ng";
        sshUser = "nix-ssh";
        sshKey = "/etc/nix/builder_ed25519";
        inherit (host.buildMachine)
          systems
          maxJobs
          speedFactor
          supportedFeatures
          ;
      }) machines;
      settings.builders-use-substitutes = true;
    };

    # Build machines are often off. Fall back to local builds quickly.
    programs.ssh.extraConfig = lib.concatMapStrings (host: ''
      Host ${host.fqdn}
        ConnectTimeout 2
    '') machines;
  })
]
