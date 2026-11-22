{ gvfs, ... }@args:
# Rescan trash directories on FUSE mounts like on NFS, so changes made on the
# server show up in the trash.
(gvfs.override (removeAttrs args [ "gvfs" ])).overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./fuse-watch.patch ];
})
