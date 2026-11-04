{ config, ... }:
{
  environment.etc."claude-code/managed-settings.json".source =
    config.carbos.claudeCode.managedSettings;
}
