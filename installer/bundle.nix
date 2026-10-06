# What carbos-install knows about each host, computed from its configuration
# so the installer never has to evaluate a flake to plan or partition.
{
  lib,
  configurations,
  prebuilt ? false,
}:
lib.mapAttrs (
  _: host:
  let
    inherit (host.config.system) build;
    disk = host.config.disko.devices.disk.main;
    partitions = lib.sort (a: b: a.priority < b.priority) (lib.attrValues disk.content.partitions);
  in
  {
    disk = disk.device;
    partitions = map (p: {
      inherit (p) name label size;
      fs = p.content.format or p.content.type;
      subvolumes = lib.sort lib.lessThan (
        lib.filter (m: m != null) (lib.mapAttrsToList (_: s: s.mountpoint) (p.content.subvolumes or { }))
      );
    }) partitions;
    formatMount = lib.getExe' build.formatMount "disko-format-mount";
    destroyFormatMount = lib.getExe' build.destroyFormatMount "disko-destroy-format-mount";
  }
  # Lets the installer work offline, at the cost of carrying the whole system.
  // lib.optionalAttrs prebuilt { system = build.toplevel; }
) configurations
