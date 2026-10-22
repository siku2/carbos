{ inputs, ... }:
{
  flake.modules.homeManager.zed =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      extensions = with (pkgs.extend inputs.zed-extensions.overlays.default).zed-extensions; [
        cargo-tom
        dockerfile
        git-firefly
        html
        json5
        nix
        sql
        toml
        wgsl-wesl
        xml
      ];

      extensionIds = map (ext: lib.removePrefix "zed-extension-" ext.pname) extensions;

      # home-manager builds the extraPackages wrapper inline and never exposes it,
      # so both of these resolve "zeditor" from PATH rather than from pkgs.
      zedPager = pkgs.writeShellScriptBin "zed-pager" ''
        ${lib.getExe pkgs.ansifilter} --text | zeditor -e -
      '';

      zedCli = pkgs.writeShellScriptBin "zed" ''
        exec zeditor "$@"
      '';

      dataDir =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "Library/Application Support/Zed"
        else
          "${config.xdg.dataHome}/zed";
    in
    {
      imports = [ inputs.zed-extensions.homeManagerModules.default ];

      home.packages = [
        zedCli
        zedPager
      ]
      # On macOS Zed starts from the app bundle, so the extraPackages wrapper
      # never sets its PATH.
      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin config.programs.zed-editor.extraPackages;

      # Zed has no setting to stop language server downloads. A read-only
      # download directory makes them fail, so only servers from PATH run.
      home.file."${dataDir}/languages".source = pkgs.emptyDirectory;

      programs.zed-editor-extensions = {
        enable = true;
        packages = extensions;
      };

      programs.zed-editor = {
        enable = true;
        defaultEditor = true;
        mutableUserKeymaps = false;
        mutableUserSettings = false;
        extraPackages = [
          pkgs.basedpyright
          pkgs.bash-language-server
          pkgs.clang-tools
          pkgs.nil
          pkgs.nixd
          pkgs.package-version-server
          pkgs.ruff
          pkgs.rust-analyzer
          pkgs.tailwindcss-language-server
          pkgs.vscode-langservers-extracted
          pkgs.vtsls
          pkgs.wgsl-analyzer
          pkgs.yaml-language-server
        ];
        userSettings = {
          auto_update = false;
          auto_update_extensions = lib.genAttrs extensionIds (_: false);
          cli_default_open_behavior = "new_window";
          edit_predictions.provider = "copilot";
          git_panel = {
            group_by = "staging";
            tree_view = true;
          };
          lsp.cargo-tom.initialization_options.hide_docs_info_message = true;
          lsp.eslint.binary = {
            path = lib.getExe' pkgs.vscode-langservers-extracted "vscode-eslint-language-server";
            arguments = [ "--stdio" ];
          };
          session.trust_all_worktrees = true;
          disable_ai = true;
          terminal.env = {
            EDITOR = "zed -ew";
            VISUAL = "zed -ew";
            PAGER = "zed-pager";
          };
        };
        userKeymaps = [
          {
            context = "Terminal && screen == alt";
            bindings = {
              ctrl-p = null;
            };
          }
        ];
      };
    };
}
