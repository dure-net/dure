{
  config,
  lib,
  pkgs,
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
      openFirewall = true;
      ed25519PrivateKeyFile = cfg.ed25519PrivateKeyFile;
      hosts = naruHostData.tincHosts;
      # Keep bootstrap topology explicit. Filtering preserves evaluation while
      # registry is empty or one relay is being provisioned.
      connectTo = lib.filter (name: naruHostData.tincHosts ? ${name}) [
        "taps"
        "eta"
      ];
      # MST broadcast loops during edge churn can amplify discovery traffic
      # edge churn amplified SSDP/IGMP into a mesh-wide packet storm.
      extraConfig = ''
        LocalDiscovery = yes
        Broadcast = no
      '';
      addresses = lib.optional (cfg.ipv4 != null) "${cfg.ipv4}/12" ++ [ "${cfg.ipv6}/16" ];
      interfaceName = "tinc.naru";
      dns = {
        enable = true;
        suffix = "n";
        address4 = "10.208.0.53";
        address6 = "fdec:ca5f::53";
      };
    };

    # Measured with `ping -6 -s 1378` across the mesh; pin it so
    # PMTU blackholes over double-NAT relays don't stall TCP.
    systemd.network.networks."40-tincr-naru".linkConfig.MTUBytes = "1377";

    networking.extraHosts = lib.mkIf cfg.extraHosts (
      if cfg.ipv4 == null then naruHostData.extraHosts.v6only else naruHostData.extraHosts.v4v6
    );

    environment.systemPackages = [
      config.services.tincr.networks.naru.package
    ];

    # Replace real directories left behind by the old services.tinc module
    # (setup-etc won't) and relink hosts to the current generation.
    # "+" runs as root since /etc/tinc is root-owned and tincd is not.
    systemd.services.tincr-naru.serviceConfig.ExecStartPre = lib.mkBefore [
      "+${pkgs.writeShellScript "tincr-naru-migrate" ''
        for name in hosts invitations; do
          d=/etc/tinc/naru/$name
          if [ -d "$d" ] && [ ! -L "$d" ]; then
            rm -rf "$d"
          fi
        done
        ln -sfn ${config.environment.etc."tinc/naru/hosts".source} /etc/tinc/naru/hosts
      ''}"
    ];
  };
}
