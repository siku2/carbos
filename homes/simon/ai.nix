{
  lib,
  pkgs,
  ...
}:
let
  secretspecManifest = ../../secretspec.toml;

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
    package = pkgs.unstable.claude-code;
    context = ./files/CLAUDE.md;
    settings = {
      env = {
        CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
      };
      includeCoAuthoredBy = false;
      permissions.defaultMode = "auto";
      enabledPlugins = {
        "rust-analyzer-lsp@claude-plugins-official" = true;
      };
      effortLevel = "high";
      skipDangerousModePermissionPrompt = true;
      theme = "dark";
      switchModelsOnFlag = false;
      inputNeededNotifEnabled = true;
      agentPushNotifEnabled = true;
    };
  };

  home.file.".claude/skills/create-pr/SKILL.md".source = ./files/skills/create-pr.md;

  programs.opencode = {
    enable = true;
    package = opencodeWithSecrets;
    extraPackages = [ pkgs.nodejs ];
    settings = {
      formatter = true;
      lsp = true;
      permission = {
        external_directory = {
          "/tmp/**" = "allow";
          "~/.cargo/git/checkouts/**" = "allow";
          "~/.cargo/registry/src/**" = "allow";
        };
        edit = {
          "~/.cargo/git/checkouts/**" = "deny";
          "~/.cargo/registry/src/**" = "deny";
        };
      };
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
