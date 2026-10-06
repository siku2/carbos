{ inputs }:
{ lib, ... }:
let
  target = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      inputs.disko.nixosModules.disko
      ./test-host.nix
    ];
  };
in
{
  name = "carbos-installer";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ./module.nix ];

      carbos.installer.bundle = {
        source = "unused-with-a-prebuilt-system";
        rev = "test";
        hosts = import ./bundle.nix {
          inherit lib;
          configurations.vm-test = target;
          prebuilt = true;
        };
      };

      boot.supportedFilesystems = [
        "btrfs"
        "vfat"
      ];

      environment.systemPackages = with pkgs; [
        btrfs-progs
        dosfstools
        e2fsprogs
        gptfdisk
        parted
      ];

      users.users.tester.isNormalUser = true;

      virtualisation = {
        useEFIBoot = true;
        emptyDiskImages = [ 8192 ];
        memorySize = 2048;
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Both GPT copies and the start of every filesystem.
    def disk_hash():
        return machine.succeed("{ head -c 64M /dev/vdb; tail -c 1M /dev/vdb; } | sha256sum")

    with subtest("a dry run needs no root and changes nothing"):
        before = disk_hash()
        out = machine.succeed("su - tester -c 'carbos-install --dry-run' 2>&1")
        assert "vm-test" in out, out
        assert "everything else is erased" in out, out
        assert before == disk_hash()

    with subtest("wipe installs onto a blank disk"):
        machine.succeed("carbos-install --unattended --mode wipe 2>&1")
        machine.succeed("test -e /mnt/nix/var/nix/profiles/system")
        machine.succeed("test -e /mnt/boot/EFI/systemd/systemd-bootx64.efi")
        machine.succeed("lsblk -nro PARTLABEL /dev/vdb | grep -x disk-main-carbos")
        machine.succeed("umount -R /mnt")

    with subtest("keep moves foreign data to /old and installs next to it"):
        machine.succeed(
            "sgdisk --zap-all /dev/vdb",
            "sgdisk -n1:0:+300M -t1:EF00 -n2:0:+300M -n3:0:0 /dev/vdb",
            "partprobe /dev/vdb && udevadm settle",
            "mkfs.vfat /dev/vdb1",
            "mkfs.ext4 -q /dev/vdb2",
            "mkfs.btrfs -q -f /dev/vdb3",
            "mkdir -p /tmp/top && mount /dev/vdb3 /tmp/top",
            "for s in root home var; do btrfs subvolume create /tmp/top/$s; done",
            "echo precious > /tmp/top/home/file",
            "umount /tmp/top",
        )
        before = disk_hash()
        out = machine.succeed("su - tester -c 'carbos-install --dry-run --mode keep' 2>&1")
        assert "kept" in out, out
        assert before == disk_hash()

        machine.succeed("carbos-install --unattended --mode keep 2>&1")
        machine.succeed("test -e /mnt/nix/var/nix/profiles/system")
        machine.succeed("blkid -s TYPE -o value /dev/vdb1 | grep -x vfat")
        machine.succeed("mount -o subvolid=5 /dev/disk/by-partlabel/disk-main-carbos /tmp/top")
        machine.succeed("grep -x precious /tmp/top/old/*/home/file")
        machine.succeed("test -d /tmp/top/old/*/var")
  '';
}
