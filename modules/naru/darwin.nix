{
  config,
  lib,
  naruHostData,
  ...
}:
let
  cfg = config.networking.naru;
in
{
  imports = [ ./common.nix ];

  config = {
    services.tincr.networks.naru = {
      nodeName = cfg.nodename;
      listenPort = cfg.port;
      ed25519PrivateKeyFile = cfg.ed25519PrivateKeyFile;
      hosts = naruHostData.tincHosts;
      # Keep bootstrap topology explicit. Filtering preserves evaluation while
      # registry is empty or one relay is being provisioned.
      connectTo = lib.filter (name: naruHostData.tincHosts ? ${name}) [
        "taps"
        "eta"
      ];
      extraConfig = ''
        LocalDiscovery = yes
        Broadcast = no
      '';
      addresses = lib.optional (cfg.ipv4 != null) "${cfg.ipv4}/12" ++ [ "${cfg.ipv6}/16" ];
    };

    # No resolved on Darwin, so the tincr DNS stub cannot be routed
    # per-suffix; fall back to a static hosts block managed with
    # BEGIN/END markers so darwin-rebuild can update it in place.
    system.activationScripts.postActivation.text = lib.mkIf cfg.extraHosts (
      let
        hostsFile =
          if cfg.ipv4 == null then naruHostData.extraHosts.v6only else naruHostData.extraHosts.v4v6;
      in
      lib.mkAfter ''
        tmp=$(mktemp /private/etc/hosts.XXXXXX)
        chmod 644 "$tmp"
        awk '
          /^# BEGIN NARU HOSTS$/ { skip=1; next }
          /^# END NARU HOSTS$/   { skip=0; next }
          !skip { print }
        ' /private/etc/hosts > "$tmp"
        {
          echo "# BEGIN NARU HOSTS"
          cat ${builtins.toFile "naru-hosts" hostsFile}
          echo "# END NARU HOSTS"
        } >> "$tmp"
        mv "$tmp" /private/etc/hosts
      ''
    );
  };
}
