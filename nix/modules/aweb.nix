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
        AWID_REGISTRY_URL = "http://${cfg.awid.host}:${toString cfg.awid.port}";
        AWEB_LOG_JSON = "true";
      };

      serviceConfig = {
        ExecStart = "${cfg.server.package}/bin/aweb";
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
