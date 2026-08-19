# Generated network artifacts for Nix and portable consumers.
{
  lib,
  runCommand,
  writeText,
  coreutils,
  gnutar,
  gzip,
}:
let
  data = import ./modules/naru/hosts.nix { inherit lib; };

  zone =
    tld: netname:
    let
      hosts = lib.filterAttrs (_: host: host.nets ? ${netname}) data.hosts;
      addressRecords = lib.concatLists (
        lib.mapAttrsToList (
          name: host:
          let
            net = host.nets.${netname};
            canonical = "${name}.${tld}";
            aliases = lib.filter (alias: alias != canonical) net.aliases;
          in
          lib.optional (net.ip4 != null) "${name} IN A ${net.ip4.addr}"
          ++ lib.optional (net.ip6 != null) "${name} IN AAAA ${net.ip6.addr}"
          ++ map (alias: "${lib.removeSuffix ".${tld}" alias} IN CNAME ${canonical}.") aliases
        ) hosts
      );
      body = lib.concatStringsSep "\n" (
        [
          "@ IN NS taps.${tld}."
          "@ IN NS eta.${tld}."
        ]
        ++ addressRecords
      );
      serial = lib.fromHexString (builtins.substring 0 8 (builtins.hashString "sha256" body));
    in
    ''
      $ORIGIN ${tld}.
      $TTL 300
      @ IN SOA taps.${tld}. hostmaster.${tld}. (
        ${toString serial} ; serial
        3600 ; refresh
        600 ; retry
        604800 ; expire
        300 ; negative ttl
      )
      ${body}
    '';

  naruHosts =
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
  etcHosts = writeText "naru-etc-hosts" data.extraHosts.v4v6;
  etcHostsV6 = writeText "naru-etc-hosts-v6only" data.extraHosts.v6only;
  nZone = writeText "n.zone" (zone "n" "naru");
  iZone = writeText "i.zone" (zone "i" "internet");
  registryJSON = writeText "registry.json" (
    builtins.toJSON {
      inherit (data) hosts users;
    }
  );
  naruHostsTarball =
    runCommand "naru-hosts.tar.gz"
      {
        nativeBuildInputs = [
          gnutar
          gzip
        ];
      }
      ''
        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
          -C ${naruHosts} -czf "$out" .
      '';
  release = runCommand "dure-release" { nativeBuildInputs = [ coreutils ]; } ''
    mkdir -p "$out"
    cp ${naruHostsTarball} "$out/naru-hosts.tar.gz"
    cp ${etcHosts} "$out/etc-hosts"
    cp ${etcHostsV6} "$out/etc-hosts-v6only"
    cp ${nZone} "$out/n.zone"
    cp ${iZone} "$out/i.zone"
    cp ${registryJSON} "$out/registry.json"
    (cd "$out" && sha256sum naru-hosts.tar.gz etc-hosts etc-hosts-v6only n.zone i.zone registry.json > SHA256SUMS)
  '';
in
{
  naru-hosts = naruHosts;
  etc-hosts = etcHosts;
  etc-hosts-v6only = etcHostsV6;
  n-zone = nZone;
  i-zone = iZone;
  registry-json = registryJSON;
  naru-hosts-tarball = naruHostsTarball;
  inherit release;
}
