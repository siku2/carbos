{
  flake.modules.nixos.agents.imports = [
    ./claude-code/nixos.nix
    ./claude-code/system.nix
    ./codex/system.nix
  ];

  flake.modules.darwin.agents.imports = [
    ./claude-code/darwin.nix
    ./claude-code/system.nix
    ./codex/system.nix
  ];

  flake.modules.homeManager.agents.imports = [
    ./claude-code/home.nix
    ./codex/home.nix
    ./opencode/home.nix
  ];
}
