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
