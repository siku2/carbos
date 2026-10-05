{ config, pkgs, ... }:
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
    ./home/claude-code.nix
    ./home/direnv.nix
    ./home/git.nix
    ./home/rdp.nix
    ./home/ssh.nix
    ./home/zsh.nix
  ];

  home = {
    username = "simon";
    stateVersion = "26.05";
  };

  rdp.connections.enif = {
    "full address" = "enif.pegasus.inomo.tech";
    username = "Administrator";
  };

  programs = {
    bash.enable = true;
    gh.enable = true;
    gpg.enable = true;

    nh = {
      enable = true;
      flake = "/etc/nix-darwin";
    };

    zed-editor = {
      enable = true;
      package = zed-editor;
      defaultEditor = true;
    };

    codex = {
      enable = true;
      # TODO: blocked by https://github.com/nix-community/home-manager/issues/9397
      # settings = {
      #   approvals_reviewer = "auto_review";

      #   model = "gpt-6-astra";
      #   model_reasoning_effort = "low";

      #   features = {
      #     prevent_idle_sleep = true;
      #   };
      # };
    };
  };

  home.packages = with pkgs; [
    age
    cargo-clean-all
    fd
    forgejo-cli
    fzf
    jq
    nil
    nixd
    nixfmt
    ripgrep
    sops
    tree
    unzip
    wget
    yq
  ];

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry_mac;
    defaultCacheTtl = 600;
    maxCacheTtl = 7200;
  };
}
