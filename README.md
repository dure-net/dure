# Dure

Dure is Dure's public registry for hosts, users, network addresses, aliases,
and public key material. Naru's NixOS and nix-darwin modules consume this data
directly and configure [tincr](https://github.com/Mic92/tincr).

Private keys do not belong here. Each member repository stores its Tinc private
key in its own secret backend.

## Data model

Each top-level directory is an owner namespace. Host records use one value per
file:

```text
<owner>/hosts/<host>/
├── ssh.pub                    # optional SSH host public key
├── naru/
│   ├── aliases               # one `.n` name per line
│   ├── ed25519.key           # Tinc SPTPS public key
│   ├── ip4                   # optional Naru IPv4 address
│   ├── ip6                   # Naru IPv6 address
│   └── via                   # `internet` for public bootstrap nodes
└── internet/
    └── addrs                 # public IP or DNS name, one per line
```

User records live under `<owner>/users/<user>/`. Full supported layout is
documented in [`default.nix`](default.nix).

## Address plan

```text
DNS suffix:  .n
IPv4:        10.208.0.0/12
IPv6:        fdec:ca5f::/32
Tinc port:   655/TCP and 655/UDP
```

IPv4 addresses are optional and allocated manually. IPv6 addresses are derived
deterministically from owner namespace and hostname.

Address prefixes come from `SHA-256("dure-net/naru")`:

```text
d3ecca5f1fc1a68eacdb6709d4a6542007d0228512a54f3495dbc8ae16cc00ce
IPv4: first nibble d → 13 × 16 → 10.208.0.0/12
IPv6: next 24 bits ec ca 5f → fdec:ca5f::/32
```

Both prefixes were checked against routes on initial Dure members. CI rejects
duplicate addresses, aliases, and public keys inside Dure.

## Add host

Run wizard from repository root:

```console
nix run .#add-host
```

Wizard generates Tinc keypair and host record. Install private half in member's
secret backend, remove temporary copy, then validate public data:

```console
nix flake check
```

For public bootstrap node, also add `internet/addrs` and set `naru/via` to
`internet`. Ordinary NATed members need no public address.

Remove host with:

```console
nix run .#remove-host
```

## NixOS

```nix
{
  inputs.dure.url = "github:dure-net/dure";

  outputs = { dure, nixpkgs, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        dure.nixosModules.naru
        {
          networking.naru.ed25519PrivateKeyFile =
            "/var/src/secrets/tinc.naru.ed25519_key.priv";
        }
      ];
    };
  };
}
```

## nix-darwin

```nix
{
  imports = [ dure.darwinModules.naru ];
  networking.naru.ed25519PrivateKeyFile =
    "/var/src/secrets/tinc.naru.ed25519_key.priv";
}
```

Static host entries keep `.n` names resolvable while tincd starts or restarts.

## Dure CA

Dure publishes the dure root and name-constrained network intermediate
certificates through `nixosModules.ca` and `darwinModules.ca`. The intermediate
is trusted by default and can issue DNS certificates only for `.n`, `.i`, `.x`,
and `.z`. The unrestricted root is not trusted by default.

```nix
{
  imports = [ dure.nixosModules.ca ];
  dure.ca.trustIntermediate = true;
}
```

Private keys remain encrypted in the operator repository. They are not stored
or deployed by Dure.

## Authoritative DNS

Dure renders the `n.` zone directly from Naru registry records. `taps.n.`
and `eta.n.` are authoritative bootstrap nameservers. Host names receive A and
AAAA records from their Naru addresses; additional `.n` aliases become CNAMEs.
The SOA serial is derived from zone contents, so identical registry data always
produces identical output.

```console
nix build .#n-zone
named-checkzone n result
kzonecheck -o n result
```

## Outputs

```console
nix build .#naru-hosts
nix build .#etc-hosts
nix build .#etc-hosts-v6only
nix build .#n-zone
```

Raw records are available as flake outputs `hosts` and `users`.
