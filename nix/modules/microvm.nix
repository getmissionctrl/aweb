# nix/modules/microvm.nix
#
# MicroVM guest configuration for the aweb coordination server.
# Runs aweb + awid + PostgreSQL + Redis as a self-contained appliance.
{ config, lib, pkgs, ... }:

{
  # --- Microvm hardware ---
  microvm = {
    hypervisor = "firecracker";
    mem = 2048;
    vcpu = 2;

    # TAP interface — the host-side module creates and bridges this
    interfaces = [{
      type = "tap";
      id = "aweb-vm";
      mac = "02:00:00:00:00:02";
    }];

    # Persistent volume for PostgreSQL data
    volumes = [{
      image = "aweb-data.img";
      mountPoint = "/var/lib/postgresql";
      size = 4096; # 4 GB
      autoCreate = true;
    }];

    # Also persist Redis appendonly data dir (optional, but cheap insurance)
    # and /var/lib/aweb for any future state
  };

  # --- Networking (static IP on scape bridge) ---
  systemd.network.enable = true;

  systemd.network.networks."10-eth" = {
    matchConfig.Name = "eth0";
    address = [ "10.99.0.2/24" ];
    gateway = [ "10.99.0.1" ];
    dns = [ "8.8.8.8" "8.8.4.4" ];
    networkConfig.DHCP = "no";
  };

  networking.firewall.enable = false;

  # --- PostgreSQL ---
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    ensureDatabases = [ "aweb" "awid" ];
    ensureUsers = [
      { name = "aweb"; ensureDBOwnership = true; }
      { name = "awid"; ensureDBOwnership = true; }
    ];
    authentication = ''
      local all all trust
      host all all 127.0.0.1/32 trust
    '';
    settings = {
      listen_addresses = "127.0.0.1";
      shared_buffers = "256MB";
      effective_cache_size = "512MB";
      max_connections = 100;
    };
  };

  # --- Redis ---
  services.redis.servers."" = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
    settings = {
      maxmemory = "128mb";
      maxmemory-policy = "allkeys-lru";
    };
  };

  # --- aweb + awid (via existing NixOS module) ---
  services.aweb = {
    enable = true;

    server = {
      host = "0.0.0.0";
      port = 8000;
      databaseUrl = "postgresql://aweb@127.0.0.1:5432/aweb";
      redisUrl = "redis://127.0.0.1:6379/0";
    };

    awid = {
      host = "0.0.0.0";
      port = 8010;
      databaseUrl = "postgresql://awid@127.0.0.1:5432/awid";
      redisUrl = "redis://127.0.0.1:6379/0";
      dbSchema = "public";
    };
  };

  # --- Minimal system ---
  system.stateVersion = "24.11";
  environment.systemPackages = [ pkgs.curl ];
  users.users.root.password = "";
  services.getty.autologinUser = "root";
}
