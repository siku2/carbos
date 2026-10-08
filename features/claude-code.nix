{ inputs, ... }:
{
  flake.modules.homeManager.claude-code =
    { pkgs, ... }:
    let
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
          "${inputs.claude-plugins-official}/plugins/rust-analyzer-lsp"
        ];
        context = ./claude/CLAUDE.md;
        rules = {
          cargo = ./claude/rules/cargo.md;
          rust = ./claude/rules/rust.md;
        };
        skills.create-pr = ./claude/skills/create-pr.md;
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
