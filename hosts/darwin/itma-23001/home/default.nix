{
  imports = [
    ./git.nix
    ./ssh.nix
  ];

  carbos.user.projectsDirectory = "/Volumes/Projects";

  rdp.connections.enif = {
    "full address" = "enif.pegasus.inomo.tech";
    username = "Administrator";
  };

  programs.bash.enable = true;
}
