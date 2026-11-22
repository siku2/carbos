{ modulesPath, ... }:
{
  imports = [ "${modulesPath}/installer/sd-card/sd-image-aarch64.nix" ];

  # Installer tools and ZFS, which the SD image pulls in.
  disabledModules = [ "profiles/base.nix" ];

  nixpkgs.hostPlatform = "aarch64-linux";

  sdImage.compressImage = false;

  hardware.enableRedistributableFirmware = true;
}
