# nix/modules/aweb.nix
#
# NixOS module for aweb server and awid identity service.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.aweb;
in
{
  options.services.aweb = {
    enable = lib.mkEnableOption "aweb coordination platform";

    server = {
      package = lib.mkOption {
        type = lib.types.package;
        description = "The aweb server package.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Host address for the aweb server to bind to.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8000;
        description = "Port for the aweb server to listen on.";
      };

      databaseUrl = lib.mkOption {
        type = lib.types.str;
        description = "PostgreSQL connection URL for the aweb server.";
      };

      redisUrl = lib.mkOption {
        type = lib.types.str;
        default = "redis://127.0.0.1:6379/0";
        description = "Redis connection URL for the aweb server.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to an environment file with secrets (e.g. JWT keys).";
      };

      publicOrigin = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://aweb.example.com";
        description = ''
          Public origin other aweb servers use for federated mail/chat delivery.
          Origin only (scheme://host[:port]); no path. Sets AWEB_PUBLIC_ORIGIN.
          Must equal the namespace default delivery origin registered in awid,
          or inbound federation fails closed.
        '';
      };

      publicRegistryUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://awid.example.com";
        description = ''
          Publicly routable origin of this deployment's awid registry, published
          in the /api/v1/discovery document (sets AWID_PUBLIC_REGISTRY_URL). The
          server talks to awid over the internal AWID_REGISTRY_URL; without this
          the discovery doc would leak that internal address (e.g. 127.0.0.1) to
          external CLI onboarding / team-registration consumers. Origin only.
        '';
      };
    };

    awid = {
      package = lib.mkOption {
        type = lib.types.package;
        description = "The awid identity service package.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Host address for the awid service to bind to.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8010;
        description = "Port for the awid service to listen on.";
      };

      databaseUrl = lib.mkOption {
        type = lib.types.str;
        description = "PostgreSQL connection URL for the awid service.";
      };

      redisUrl = lib.mkOption {
        type = lib.types.str;
        default = "redis://127.0.0.1:6379/0";
        description = "Redis connection URL for the awid service.";
      };

      dbSchema = lib.mkOption {
        type = lib.types.str;
        default = "awid";
        description = "PostgreSQL schema name for awid tables.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to an environment file with secrets for awid.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.awid = {
      description = "awid identity registry service";
      after = [ "network.target" "postgresql.target" "redis.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        AWID_DATABASE_URL = cfg.awid.databaseUrl;
        AWID_REDIS_URL = cfg.awid.redisUrl;
        AWID_HOST = cfg.awid.host;
        AWID_PORT = toString cfg.awid.port;
        AWID_DB_SCHEMA = cfg.awid.dbSchema;
        AWID_LOG_JSON = "true";
        AWID_RATE_LIMIT_BACKEND = "redis";
      };

      serviceConfig = {
        ExecStart = "${cfg.awid.package}/bin/awid";
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        Restart = "on-failure";
        RestartSec = 5;
      } // lib.optionalAttrs (cfg.awid.environmentFile != null) {
        EnvironmentFile = cfg.awid.environmentFile;
      };
    };

    systemd.services.aweb = {
      description = "aweb coordination server";
      after = [ "network.target" "awid.service" "postgresql.target" "redis.service" ];
      requires = [ "awid.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        AWEB_DATABASE_URL = cfg.server.databaseUrl;
        AWEB_REDIS_URL = cfg.server.redisUrl;
        AWEB_HOST = cfg.server.host;
        AWEB_PORT = toString cfg.server.port;
        AWID_REGISTRY_URL = "http://127.0.0.1:${toString cfg.awid.port}";
        AWEB_LOG_JSON = "true";
      } // lib.optionalAttrs (cfg.server.publicOrigin != null) {
        AWEB_PUBLIC_ORIGIN = cfg.server.publicOrigin;
      } // lib.optionalAttrs (cfg.server.publicRegistryUrl != null) {
        AWID_PUBLIC_REGISTRY_URL = cfg.server.publicRegistryUrl;
      };

      serviceConfig = {
        ExecStart = "${cfg.server.package}/bin/aweb serve";
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        Restart = "on-failure";
        RestartSec = 5;
      } // lib.optionalAttrs (cfg.server.environmentFile != null) {
        EnvironmentFile = cfg.server.environmentFile;
      };
    };
  };
}
