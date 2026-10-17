{ dms-shell }:
# Until DMS 1.6, which has customPowerButtons, reaches stable nixpkgs.
dms-shell.overrideAttrs (old: {
  postInstall = old.postInstall + ''
    chmod -R u+w $out/share/quickshell/dms
    patch -d $out/share/quickshell/dms -p1 < ${./monitors-off.patch}
  '';
})
