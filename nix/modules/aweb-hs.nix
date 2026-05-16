# nix/modules/aweb-hs.nix
#
# NixOS module for the aweb Haskell coordination server.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.aweb.hs;
in
{
  options.services.aweb.hs = {
    enable = lib.mkEnableOption "aweb Haskell coordination server";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The aweb-hs server package.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for the aweb-hs server to listen on.";
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      description = "PostgreSQL connection URL for the aweb-hs server.";
    };

    natsUrl = lib.mkOption {
      type = lib.types.str;
      default = "nats://127.0.0.1:4222";
      description = "NATS server URL.";
    };

    awidUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8010";
      description = "awid registry URL for DID resolution.";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "info";
      description = "Log level (debug, info, warn, error).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.aweb-hs = {
      description = "aweb Haskell coordination server";
      after = [ "network.target" "postgresql.target" "nats.service" "awid.service" ];
      wants = [ "nats.service" "awid.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = lib.concatStringsSep " " [
          "${cfg.package}/bin/aweb-hs"
          "--port ${toString cfg.port}"
          "--database-url \"${cfg.databaseUrl}\""
          "--nats-url \"${cfg.natsUrl}\""
          "--awid-url \"${cfg.awidUrl}\""
          "--log-level \"${cfg.logLevel}\""
        ];
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
