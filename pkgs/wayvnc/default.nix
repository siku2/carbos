{ wayland-protocols, wayvnc }:
wayvnc.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    # With wlr-screencopy, wayvnc allocates buffers on the first GPU it finds.
    # This takes the compositor's main device from linux-dmabuf feedback instead.
    ./dmabuf-main-device.patch
    # Crashes on disconnect after the captured output went away.
    ./missing-output.patch
  ];

  # The bundled protocol predates feedback.
  postPatch = (old.postPatch or "") + ''
    cp ${wayland-protocols}/share/wayland-protocols/stable/linux-dmabuf/linux-dmabuf-v1.xml \
      protocols/linux-dmabuf-unstable-v1.xml
  '';
})
