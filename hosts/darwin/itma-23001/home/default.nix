{
  config,
  inputs,
  pkgs,
  ...
}:
let
  # The Zed CLI opens the bundle it lives in. Use the copy made by
  # targets.darwin.copyApps, otherwise it starts the store bundle, which hands
  # off to the running instance and the open request is lost.
  zed-editor = pkgs.symlinkJoin {
    name = "zed-editor-${pkgs.zed-editor.version}";
    paths = [ pkgs.zed-editor ];
    postBuild = ''
      rm $out/bin/zeditor
      cat > $out/bin/zeditor <<EOF
      #!${pkgs.runtimeShell}
      exec "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Zed.app/Contents/MacOS/cli" "\$@"
      EOF
      chmod +x $out/bin/zeditor
    '';
    inherit (pkgs.zed-editor) meta;
  };
in
{
  imports = [
    ./git.nix
    ./ssh.nix
    ./zsh.nix
  ]
  ++ (with inputs.self.modules.homeManager; [
    claude-code
    cli
    codex
    direnv
    git
    rdp
    starship
  ]);

  carbos.user = {
    fullName = "Simon Berger";
    email = "simon.berger@inomotech.com";
  };

  home = {
    username = "simon";
    stateVersion = "26.05";

    packages = with pkgs; [
      cargo-clean-all
      forgejo-cli
      nil
      nixd
      nixfmt
    ];
  };

  rdp.connections.enif = {
    "full address" = "enif.pegasus.inomo.tech";
    username = "Administrator";
  };

  programs = {
    bash.enable = true;
    gh.enable = true;
    gpg.enable = true;

    direnv.config.whitelist.prefix = [ "/Volumes/Projects" ];

    nh = {
      enable = true;
      flake = "/etc/nix-darwin";
    };

    zed-editor = {
      enable = true;
      package = zed-editor;
      defaultEditor = true;
    };
  };

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry_mac;
    defaultCacheTtl = 600;
    maxCacheTtl = 7200;
  };
}
