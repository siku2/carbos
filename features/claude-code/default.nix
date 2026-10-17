{ inputs, ... }:
let
  managedSettings = {
    imports = [ ./managed-settings.nix ];
    carbos.claudeCode.managedSettings.strictKnownMarketplaces = [ { source = "skills-dir"; } ];
  };
in
{
  flake.modules.nixos.claude-code =
    { config, ... }:
    {
      imports = [ managedSettings ];
      environment.etc."claude-code/managed-settings.json".source =
        config.carbos.claudeCode.managedSettings;
    };

  flake.modules.darwin.claude-code =
    { config, ... }:
    {
      imports = [ managedSettings ];
      system.activationScripts.postActivation.text = ''
        mkdir -p "/Library/Application Support/ClaudeCode"
        cp ${config.carbos.claudeCode.managedSettings} "/Library/Application Support/ClaudeCode/managed-settings.json"
      '';
    };

  flake.modules.homeManager.claude-code =
    { lib, pkgs, ... }:
    let
      marketplace = lib.importJSON "${inputs.claude-plugins-official}/.claude-plugin/marketplace.json";

      # Some marketplace plugins keep their manifest in marketplace.json and
      # ship an empty directory, so --plugin-dir alone loads nothing.
      pluginFromMarketplace =
        name:
        let
          entry = lib.findFirst (p: p.name == name) (throw "no plugin ${name}") marketplace.plugins;
        in
        pkgs.writeTextFile {
          inherit name;
          destination = "/.claude-plugin/plugin.json";
          text = builtins.toJSON (
            removeAttrs entry [
              "source"
              "category"
              "strict"
            ]
          );
        };

      # No settings key exists for this. The flag only makes bypass mode
      # selectable, defaultMode below still decides how a session starts.
      claudeCodeAllowingBypass = pkgs.symlinkJoin {
        name = "claude-code-allow-bypass";
        paths = [ pkgs.claude-code ];
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          wrapProgram $out/bin/claude \
            --inherit-argv0 \
            --add-flags --allow-dangerously-skip-permissions
        '';
        inherit (pkgs.claude-code) meta;
      };
    in
    {
      programs.claude-code = {
        enable = true;
        package = claudeCodeAllowingBypass;
        plugins = [
          "${inputs.claude-plugins-official}/plugins/frontend-design"
          (pluginFromMarketplace "rust-analyzer-lsp")
        ];
        context = ./CLAUDE.md;
        rules = {
          cargo = ./rules/cargo.md;
          rust = ./rules/rust.md;
        };
        skills.create-pr = ./skills/create-pr.md;
        settings = {
          attribution = {
            commit = "";
            pr = "";
            sessionUrl = false;
          };
          env = {
            CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
          };
          permissions.defaultMode = "auto";
          askUserQuestionTimeout = "10m";
          enableArtifact = false;
          feedbackDrafts = "off";
          skipDangerousModePermissionPrompt = true;
          skipWorkflowUsageWarning = true;
          theme = "dark";
          switchModelsOnFlag = false;
          inputNeededNotifEnabled = true;
          agentPushNotifEnabled = true;
          remoteControlAtStartup = false;
        };
      };
    };
}
