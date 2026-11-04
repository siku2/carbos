{
  imports = [ ./module.nix ];

  carbos.claudeCode.managedSettings.strictKnownMarketplaces = [ { source = "skills-dir"; } ];
}
