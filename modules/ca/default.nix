{ config, lib, ... }:
let
  cfg = config.dure.ca;
in
{
  options.dure.ca = {
    rootCA = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = builtins.readFile ./root-ca.crt;
      defaultText = "root-ca.crt";
      description = "dure root ca certificate.";
    };
    intermediateCA = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = builtins.readFile ./intermediate-ca.crt;
      defaultText = "intermediate-ca.crt";
      description = "name-constrained dure intermediate ca certificate.";
    };
    acmeURL = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "https://ca.n/acme/acme/directory";
      description = "dure acme directory.";
    };
    trustRoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Trust the dure root ca system-wide. This permits certificates for any
        domain, so leave it disabled unless unrestricted dure trust is needed.
      '';
    };
    trustIntermediate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Trust the dure network intermediate system-wide. Its critical name
        constraints limit dns issuance to .n, .i, .x, and .z.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.trustRoot { security.pki.certificates = [ cfg.rootCA ]; })
    (lib.mkIf cfg.trustIntermediate { security.pki.certificates = [ cfg.intermediateCA ]; })
  ];
}
