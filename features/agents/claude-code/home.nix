{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  marketplace = lib.importJSON "${inputs.claude-plugins-official}/.claude-plugin/marketplace.json";

  # Some marketplace plugins keep their manifest in marketplace.json and
  # ship an empty directory, so --plugin-dir alone loads nothing.
  pluginFromMarketplace =
    name: overrides:
    let
      entry = lib.findFirst (p: p.name == name) (throw "no plugin ${name}") marketplace.plugins;
    in
    pkgs.writeTextFile {
      inherit name;
      destination = "/.claude-plugin/plugin.json";
      text = builtins.toJSON (
        removeAttrs (lib.recursiveUpdate entry overrides) [
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
    # nixpkgs defaults to system-only trust, which fails on macOS here.
    # Restore Claude's default before the inner wrapper sets its fallback.
    postBuild = ''
      wrapProgram $out/bin/claude \
        --inherit-argv0 \
        --set-default CLAUDE_CODE_CERT_STORE bundled,system \
        --add-flags --allow-dangerously-skip-permissions \
        --suffix PATH : ${
          lib.makeBinPath [
            pkgs.basedpyright
            pkgs.rust-analyzer
            pkgs.vtsls
          ]
        }
    '';
    inherit (pkgs.claude-code) meta;
  };

  # Some safety checks still prompt in bypass mode and block the session
  # until answered. Deny them so the agent can choose another approach.
  denyPromptsInBypass = pkgs.writeShellApplication {
    name = "claude-deny-prompts-in-bypass";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      if jq -e '.permission_mode == "bypassPermissions"' >/dev/null; then
        jq -n '{
          hookSpecificOutput: {
            hookEventName: "PermissionRequest",
            decision: {
              behavior: "deny",
              message: "Denied automatically: static safety analysis flagged this command because it could not verify what the command affects. Rewrite it so its targets are explicit, for example with literal paths instead of variables or command substitutions."
            }
          }
        }'
      fi
    '';
  };
in
{
  programs.claude-code = {
    enable = true;
    package = claudeCodeAllowingBypass;
    plugins = [
      "${inputs.claude-plugins-official}/plugins/frontend-design"
      (pluginFromMarketplace "pyright-lsp" {
        lspServers.pyright.command = "basedpyright-langserver";
      })
      (pluginFromMarketplace "rust-analyzer-lsp" { })
      (pluginFromMarketplace "typescript-lsp" {
        lspServers.typescript.command = "vtsls";
      })
    ];
    context = ./CLAUDE.md;
    rules = {
      cargo = ./rules/cargo.md;
      github-actions = ./rules/github-actions.md;
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
      hooks.PermissionRequest = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = lib.getExe denyPromptsInBypass;
            }
          ];
        }
      ];
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
}
