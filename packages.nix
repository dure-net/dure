# Generated Naru network artifacts for consumers that do not evaluate modules.
{
  lib,
  runCommand,
  writeText,
}:
let
  data = import ./modules/naru/hosts.nix { inherit lib; };

  naruHosts = lib.filterAttrs (_: host: host.nets ? naru) data.hosts;
  addressRecords = lib.concatLists (
    lib.mapAttrsToList (
      name: host:
      let
        net = host.nets.naru;
        canonical = "${name}.n";
        aliases = lib.filter (alias: alias != canonical) net.aliases;
      in
      lib.optional (net.ip4 != null) "${name} IN A ${net.ip4.addr}"
      ++ lib.optional (net.ip6 != null) "${name} IN AAAA ${net.ip6.addr}"
      ++ map (alias: "${lib.removeSuffix ".n" alias} IN CNAME ${canonical}.") aliases
    ) naruHosts
  );
  zoneBody = lib.concatStringsSep "\n" (
    [
      "@ IN NS taps.n."
      "@ IN NS eta.n."
    ]
    ++ addressRecords
  );
  serial = lib.fromHexString (builtins.substring 0 8 (builtins.hashString "sha256" zoneBody));
  nZone = ''
    $ORIGIN n.
    $TTL 300
    @ IN SOA taps.n. hostmaster.n. (
      ${toString serial} ; serial
      3600 ; refresh
      600 ; retry
      604800 ; expire
      300 ; negative ttl
    )
    ${zoneBody}
  '';
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
  n-zone = writeText "n.zone" nZone;
}
