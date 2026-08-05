# nix/modules/microvm-host.nix
#
# Host-side NixOS module for running the aweb microVM.
# Import this in the host machine's NixOS configuration.
#
# Usage (in host infrastructure):
#   imports = [ inputs.aweb.nixosModules.microvm ];
{ config, lib, pkgs, ... }:

let
  cfg = config.services.aweb-vm;
in
{
  options.services.aweb-vm = {
    enable = lib.mkEnableOption "aweb coordination server microVM";

    ip = lib.mkOption {
      type = lib.types.str;
      default = "10.99.0.2";
      description = "Static IP address for the aweb microVM on the bridge network.";
    };

    tapInterface = lib.mkOption {
      type = lib.types.str;
      default = "aweb-vm";
      description = "TAP interface name for the microVM.";
    };

    bridge = lib.mkOption {
      type = lib.types.str;
      default = "scape-br0";
      description = "Bridge interface the TAP device joins.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      description = "The microVM runner package (declaredRunner).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/aweb-vm";
      description = "Directory for microVM state and persistent volumes.";
    };

    publicOrigin = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://aweb.example.com";
      description = ''
        Public federation origin, forwarded into the guest microVM's
        services.aweb.server.publicOrigin (sets AWEB_PUBLIC_ORIGIN in the VM).
      '';
    };

    publicRegistryUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://awid.example.com";
      description = ''
        Publicly routable awid registry origin, forwarded into the guest
        microVM's services.aweb.server.publicRegistryUrl (sets
        AWID_PUBLIC_REGISTRY_URL in the VM so the discovery doc advertises the
        public registry instead of the internal address).
      '';
    };

    registryUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://api.awid.ai";
      description = ''
        Override the guest's home registry (services.aweb.server.registryUrl →
        AWID_REGISTRY_URL). Set to https://api.awid.ai to enable per-domain
        cross-registry resolution. Null keeps the co-located local awid.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # TAP device for the microVM
    systemd.network.netdevs."20-${cfg.tapInterface}" = {
      netdevConfig = {
        Kind = "tap";
        Name = cfg.tapInterface;
      };
    };

    # Join the TAP device to the bridge
    systemd.network.networks."20-${cfg.tapInterface}" = {
      matchConfig.Name = cfg.tapInterface;
      networkConfig.Bridge = cfg.bridge;
    };

    # systemd service that runs the microVM
    systemd.services.aweb-vm = {
      description = "aweb coordination server microVM";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "systemd-networkd.service" ];
      wants = [ "systemd-networkd.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/microvm-run";
        ExecStop = "${cfg.package}/bin/microvm-shutdown";
        Restart = "on-failure";
        RestartSec = 10;
        WorkingDirectory = cfg.dataDir;
        StateDirectory = "aweb-vm";
        TimeoutStopSec = 30;
      };
    };

    # Firewall: allow agent VMs to reach aweb and awid
    networking.firewall.interfaces.${cfg.bridge} = {
      allowedTCPPorts = [ 8000 8010 ];
    };
  };
}
