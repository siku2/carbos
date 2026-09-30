{
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config = {
      whitelist = {
        prefix = [ "/Volumes/Projects" ];
      };
    };

    stdlib = ''
      use_preset() {
        if [ ''$# -eq 0 ]; then
          log_error "use preset: expected at least one preset name"
          return 1
        fi

        local names
        names="''$(printf '%s\n' "''$@" | sort -u | tr '\n' '+' | sed 's/+''$//')"

        use flake "path:/private/etc/nix-darwin#''${names}"
      }
    '';
  };
}
