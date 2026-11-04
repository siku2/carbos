{
  imports = [ ./ssh.nix ];

  carbos.user = {
    projectsDirectory = "/Volumes/Projects";
    signing = {
      format = "openpgp";
      key = "BAA343801A190591C8667BDFDA52A1F326E417A2";
    };
  };

  rdp.connections.enif = {
    "full address" = "enif.pegasus.inomo.tech";
    username = "Administrator";
  };
}
