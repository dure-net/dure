# Derive the naru peer set directly from dure's flat file tree.
{ lib }:
let
  data = import ../../. { inherit lib; };

  naruHosts = lib.filterAttrs (_: h: h.nets.naru.tinc or null != null) data.hosts;

  # tincr is SPTPS-only; drop legacy RSA-only entries so the daemon
  # does not log a refusal per connection attempt.
  sptpsHosts = lib.filterAttrs (_: h: h.nets.naru.tinc.pubkey_ed25519 != null) naruHosts;

  # Render a tinc host file.  Hosts with a via net (usually internet)
  # are reachable there directly (Address); everyone else is relayed.
  tincHostFile =
    name: h:
    let
      net = h.nets.naru;
      tinc = net.tinc;
      via = if net.via != null then h.nets.${net.via} else null;
    in
    lib.concatStringsSep "\n" (
      lib.optionals (via != null) (map (a: "Address = ${a} ${toString tinc.port}") via.addrs)
      ++ map (a: "Subnet = ${a}") tinc.subnets
      ++ map (a: "Subnet = ${a}") net.addrs
      # bare labels: the DNS stub appends its suffix
      ++ map (a: "Alias = ${a}") (
        lib.filter (a: a != name && !lib.hasInfix "." a) (
          map (lib.removeSuffix ".n") (lib.filter (lib.hasSuffix ".n") net.aliases)
        )
      )
      ++ [ tinc.extraConfig ]
      ++ lib.optional (tinc.pubkey != null) tinc.pubkey
      ++ lib.optional (tinc.pubkey_ed25519 != null) ''
        Ed25519PublicKey = ${tinc.pubkey_ed25519}
      ''
      ++ lib.optional (tinc.weight != null) "Weight = ${toString tinc.weight}"
    );

  tincHosts = lib.mapAttrs tincHostFile sptpsHosts;

  netHostsLines =
    netname: tld: hosts: withV4:
    lib.concatStrings (
      lib.mapAttrsToList (
        name: h:
        let
          net = h.nets.${netname};
          aliases = lib.concatStringsSep " " (lib.unique ([ "${name}.${tld}" ] ++ net.aliases));
        in
        lib.optionalString (withV4 && net.ip4 != null) "${net.ip4.addr} ${aliases}\n"
        + lib.optionalString (net.ip6 != null) "${net.ip6.addr} ${aliases}\n"
      ) hosts
    );

  internetHosts = lib.filterAttrs (_: h: h.nets ? internet) data.hosts;

  # withV4 only concerns naru; internet hosts always get A records.
  hostsLines =
    withV4: netHostsLines "naru" "n" naruHosts withV4 + netHostsLines "internet" "i" internetHosts true;

  own = lib.mapAttrs (_: h: {
    ip4 = h.nets.naru.ip4.addr or null;
    ip6 = h.nets.naru.ip6.addr or null;
  }) naruHosts;
in
{
  inherit tincHosts own;
  inherit (data) hosts users;
  extraHosts = {
    v4v6 = hostsLines true;
    v6only = hostsLines false;
  };
}
