{ config, ... }:
{
  system.activationScripts.postActivation.text = ''
    mkdir -p "/Library/Application Support/ClaudeCode"
    cp ${config.carbos.claudeCode.managedSettings} "/Library/Application Support/ClaudeCode/managed-settings.json"
  '';
}
