{ quickshell, fetchFromGitea }:
# 0.3.1 fixes a ScriptModel use-after-free that crashed DMS on monitor
# reconnect. Drop this once stable nixpkgs ships 0.3.2 or newer.
quickshell.overrideAttrs (old: {
  version = "0.3.2";
  src = fetchFromGitea {
    domain = "git.outfoxxed.me";
    owner = "quickshell";
    repo = "quickshell";
    tag = "v0.3.2";
    hash = "sha256-lPbqsyAD5ZoGFMZ1eqAlTULfeP5Nwhy+XvOowF7BE+E=";
  };
  patches = (old.patches or [ ]) ++ [ ./output-tracking.patch ];
})
