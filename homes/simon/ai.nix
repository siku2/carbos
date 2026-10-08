{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  secretspecManifest = ../../secretspec.toml;

  # No settings key exists for this. The flag only makes bypass mode
  # selectable, defaultMode below still decides how a session starts.
  claudeCodeAllowingBypass = pkgs.unstable.symlinkJoin {
    name = "claude-code-allow-bypass";
    paths = [ pkgs.unstable.claude-code ];
    nativeBuildInputs = [ pkgs.unstable.makeBinaryWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude \
        --inherit-argv0 \
        --add-flags --allow-dangerously-skip-permissions
    '';
    inherit (pkgs.unstable.claude-code) meta;
  };

  opencodeWithSecrets = pkgs.writeShellScriptBin "opencode" ''
    exec ${lib.getExe pkgs.unstable.secretspec} --file ${secretspecManifest} run \
      --scope opencode \
      --caller opencode \
      --reason "opencode needs the Z.ai key for its MCP servers" \
      -- ${lib.getExe pkgs.unstable.opencode} "$@"
  '';
in
{
  programs.claude-code = {
    enable = true;
    package = claudeCodeAllowingBypass;
    plugins = [
      "${inputs.claude-plugins-official}/plugins/frontend-design"
      "${inputs.claude-plugins-official}/plugins/rust-analyzer-lsp"
    ];
    context = ./files/claude/CLAUDE.md;
    rules = {
      cargo = ./files/claude/rules/cargo.md;
      rust = ./files/claude/rules/rust.md;
    };
    skills.create-pr = ./files/claude/skills/create-pr.md;
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

  programs.opencode = {
    enable = true;
    package = opencodeWithSecrets;
    extraPackages = [ pkgs.nodejs ];
    settings = {
      formatter = true;
      lsp = true;
      mcp = {
        web-reader = {
          type = "remote";
          url = "https://api.z.ai/api/mcp/web_reader/mcp";
          headers.Authorization = "Bearer {env:ZAI_API_KEY}";
        };
        web-search-prime = {
          type = "remote";
          url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
          headers.Authorization = "Bearer {env:ZAI_API_KEY}";
        };
        zread = {
          type = "remote";
          url = "https://api.z.ai/api/mcp/zread/mcp";
          headers.Authorization = "Bearer {env:ZAI_API_KEY}";
        };
        zai-mcp-server = {
          type = "local";
          command = [
            "npx"
            "-y"
            "@z_ai/mcp-server"
          ];
          environment = {
            Z_AI_API_KEY = "{env:ZAI_API_KEY}";
            Z_AI_MODE = "ZAI";
          };
        };
      };
    };

    agents = {
      orchestrator = ./files/opencode-agents/orchestrator.md;
      worker = ./files/opencode-agents/worker.md;
    };
  };

  programs.codex = {
    enable = true;
    package = pkgs.unstable.codex;
  };
}
