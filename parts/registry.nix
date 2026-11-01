{ config, lib, ... }:
let
  inherit (lib) mkOption types;

  cfg = config.carbos.registry;

  sshKey = types.submodule (
    { config, ... }:
    {
      options = {
        algorithm = mkOption {
          type = types.enum [ "ssh-ed25519" ];
        };
        key = mkOption {
          type = types.strMatching "[A-Za-z0-9+/]+=*";
        };
        comment = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        line = mkOption {
          type = types.str;
          readOnly = true;
          default = lib.concatStringsSep " " (
            [
              config.algorithm
              config.key
            ]
            ++ lib.optional (config.comment != null) config.comment
          );
          description = "The key as a public key line.";
        };
      };
    }
  );

  # A name in sshKeys, resolved to the key itself.
  sshKeyName = types.enum (lib.attrNames cfg.sshKeys);

  buildMachine = types.submodule {
    options = {
      systems = mkOption {
        type = types.listOf types.str;
        default = [ "x86_64-linux" ];
      };
      maxJobs = mkOption {
        type = types.ints.positive;
      };
      speedFactor = mkOption {
        type = types.ints.positive;
        default = 1;
      };
      supportedFeatures = mkOption {
        type = types.listOf types.str;
        default = [
          "big-parallel"
          "benchmark"
          "kvm"
          "nixos-test"
        ];
      };
    };
  };

  builder = types.submodule {
    options = {
      key = mkOption {
        type = sshKeyName;
        apply = name: cfg.sshKeys.${name};
        description = "Public half of /etc/nix/builder_ed25519, which root uses to reach the build machines.";
      };
      machines = mkOption {
        type = types.listOf (types.enum (lib.attrNames cfg.hosts));
        description = "Hosts to offload builds to.";
      };
    };
  };

  host = types.submodule (
    { name, ... }:
    {
      options = {
        fqdn = mkOption {
          type = types.str;
          default = "${name}.local.bg12.ch";
        };
        hostKey = mkOption {
          type = types.nullOr sshKey;
          default = null;
          description = "The host key of sshd.";
        };
        buildMachine = mkOption {
          type = types.nullOr buildMachine;
          default = null;
          description = "Accept builds from the hosts that list this one in builder.machines.";
        };
        builder = mkOption {
          type = types.nullOr builder;
          default = null;
          description = "Offload builds to other hosts.";
        };
      };
    }
  );

  module = {
    options.carbos.registry = mkOption {
      type = types.raw;
      # Forced, so every host checks every entry and not just the ones it reads.
      default = builtins.deepSeq cfg cfg;
      readOnly = true;
      description = "The flake's host and key registry.";
    };
  };
in
{
  imports = [ ../hosts/registry.nix ];

  options.carbos.registry = {
    hosts = mkOption {
      type = types.attrsOf host;
      default = { };
    };
    sshKeys = mkOption {
      type = types.attrsOf sshKey;
      default = { };
      description = "Keys used to connect. User keys are named after their entries in Vaultwarden.";
    };
  };

  config.flake.modules = {
    nixos.registry = module;
    darwin.registry = module;
  };
}
