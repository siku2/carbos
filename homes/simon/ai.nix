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
}
