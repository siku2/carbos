{ rclone }:
# Adds the webdav option nextcloud_trash_dir, which serves the Nextcloud trash
# bin as a freedesktop.org trash directory in the root of a mount.
rclone.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./nextcloud-trash.patch ];
})
