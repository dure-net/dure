# Generated Naru network artifacts for consumers that do not evaluate modules.
{
  lib,
  runCommand,
  writeText,
}:
let
  data = import ./modules/naru/hosts.nix { inherit lib; };
in
{
  naru-hosts =
    runCommand "naru-hosts"
      {
        passAsFile = [ "script" ];
        script = lib.concatStrings (
          lib.mapAttrsToList (name: text: ''
            cat > "$out/${name}" <<'EOF'
            ${text}
            EOF
          '') data.tincHosts
        );
      }
      ''
        mkdir -p "$out"
        bash "$scriptPath"
      '';

  etc-hosts = writeText "naru-etc-hosts" data.extraHosts.v4v6;
  etc-hosts-v6only = writeText "naru-etc-hosts-v6only" data.extraHosts.v6only;
}
