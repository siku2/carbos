{
  dms,
  declared,
  jq,
  nodejs-slim,
  runCommand,
}:
runCommand "dms-settings.json"
  {
    nativeBuildInputs = [
      jq
      nodejs-slim
    ];
    declared = builtins.toJSON declared;
    passAsFile = [ "declared" ];
  }
  ''
    node ${./spec.ts} ${dms}/share/quickshell/dms > spec.json
    jq --slurpfile spec spec.json -f ${./settings.jq} "$declaredPath" > $out
  ''
