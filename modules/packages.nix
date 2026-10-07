{
  nixpkgs.overlays = [
    (final: _prev: {
      rlbot = final.callPackage ../pkgs/rlbot { };
    })
  ];
}
