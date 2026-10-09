{
  flake.modules.homeManager.zed =
    { lib, pkgs, ... }:
    let
      # home-manager builds the extraPackages wrapper inline and never exposes it,
      # so both of these resolve "zeditor" from PATH rather than from pkgs.
      zedPager = pkgs.writeShellScriptBin "zed-pager" ''
        ${lib.getExe pkgs.ansifilter} --text | zeditor -e -
      '';

      zedCli = pkgs.writeShellScriptBin "zed" ''
        exec zeditor "$@"
      '';
    in
    {
      home.packages = [
        zedCli
        zedPager
      ];

      programs.zed-editor = {
        enable = true;
        defaultEditor = true;
        extraPackages = [
          pkgs.bash-language-server
          pkgs.nil
          pkgs.nixd
          pkgs.package-version-server
          pkgs.vscode-langservers-extracted
        ];
        extensions = [
          "cargo-tom"
          "dockerfile"
          "git-firefly"
          "html"
          "nix"
          "sql"
          "toml"
          "xml"
        ];
        userSettings = {
          auto_update = false;
          cli_default_open_behavior = "new_window";
          edit_predictions.provider = "copilot";
          git_panel.tree_view = true;
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
            context = "Terminal";
            bindings = {
              ctrl-p = null;
            };
          }
        ];
      };
    };
}
