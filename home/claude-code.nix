{ pkgs, ... }:
let
  claude-plugins-official = pkgs.fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-plugins-official";
    rev = "517b2fcd1b60fa2181ac52dcf8492361ba341180";
    hash = "sha256-BkkIWwbGj8RtGFCXY3+McPzLmP9pYhWMAmpZsVUMi4M=";
  };

  claude-code = pkgs.symlinkJoin {
    name = "claude-code";
    paths = [ pkgs.claude-code ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude --add-flags --allow-dangerously-skip-permissions
    '';
    inherit (pkgs.claude-code) meta;
  };
in
{
  programs.claude-code = {
    enable = true;
    package = claude-code;
    plugins = [
      "${claude-plugins-official}/plugins/frontend-design"
      "${claude-plugins-official}/plugins/rust-analyzer-lsp"
    ];
    context = ./claude-code/CLAUDE.md;
    rules = {
      cargo = ./claude-code/rules/cargo.md;
      rust = ./claude-code/rules/rust.md;
    };
    settings = {
      env = {
        CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
      };
      attribution = {
        commit = "";
        pr = "";
        sessionUrl = false;
      };
      enableArtifact = false;
      feedbackDrafts = "off";
      askUserQuestionTimeout = "10m";
      skipDangerousModePermissionPrompt = true;
      skipWorkflowUsageWarning = true;
      switchModelsOnFlag = false;
    };
  };
}
