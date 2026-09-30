{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "*" = {
        # Need to override this because the macOS default is just "UTF-8".
        SendEnv = "LC_CTYPE";
        SetEnv.LC_CTYPE = "en_US.UTF-8";
      };

      olu-dev-proxy = {
        HostName = "autopi-1faf5d7aad13afa15bae7497fdce0f00";
        User = "pi";
      };

      olu-dev = {
        HostName = "192.168.1.101";
        ProxyJump = "olu-dev-proxy";
        User = "root";
        IdentityFile = "~/Documents/certificates/olu-dev/id_ssh_dev10";
        PubkeyAcceptedKeyTypes = "+ssh-rsa";
        HostKeyAlgorithms = "+ssh-rsa";
      };

      tailscale-relay = {
        HostName = "tailscale-relay.bt12.inomo.tech";
        User = "simon";
      };

      forgejo-runner = {
        HostName = "forgejo-runner.bt12.inomo.tech";
        User = "simon";
      };

      github-runner = {
        HostName = "github-runner.bt12.inomo.tech";
        User = "simon";
      };

      sw1 = {
        HostName = "sw1.bt12.inomo.tech";
        User = "manager";
        KexAlgorithms = "+diffie-hellman-group14-sha1";
        HostKeyAlgorithms = "+ssh-rsa";
      };
    };
  };
}
