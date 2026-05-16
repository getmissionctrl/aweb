# aweb Server MicroVM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a Firecracker microVM that runs the full aweb stack (aweb + awid + PostgreSQL + Redis) as a self-contained appliance for the scape host.

**Architecture:** A new NixOS microVM configuration in the aweb repo using microvm.nix. The guest reuses the existing `services.aweb` NixOS module with standard nixpkgs PostgreSQL and Redis. A companion host-side module defines the TAP device and systemd service for consumption by missionctrl-infra.

**Tech Stack:** Nix flakes, microvm.nix, NixOS modules, Firecracker, PostgreSQL 16, Redis, systemd-networkd

**Spec:** `docs/superpowers/specs/2026-05-16-aweb-microvm-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `flake.nix` | Modify | Add microvm input, nixosConfigurations.microvm, packages.microvm, nixosModules.microvm |
| `nix/modules/microvm.nix` | Create | Guest NixOS configuration (services, networking, storage) |
| `nix/modules/microvm-host.nix` | Create | Host-side module (TAP device, bridge, systemd service) |

---

### Task 1: Add microvm.nix flake input

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Add the microvm input to flake.nix**

Add the microvm input after the devshell input in `flake.nix`:

```nix
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

Also add `microvm` to the outputs function arguments. Change:

```nix
  outputs = { self, nixpkgs, devshell, ... }:
```

to:

```nix
  outputs = { self, nixpkgs, devshell, microvm, ... }:
```

- [ ] **Step 2: Lock the new input**

Run: `nix flake lock --update-input microvm`

Expected: `flake.lock` updated with microvm.nix entry, no errors.

- [ ] **Step 3: Verify existing builds still work**

Run: `nix build .#aw --dry-run`

Expected: No evaluation errors. The existing packages are unaffected.

- [ ] **Step 4: Commit**

```bash
git add flake.nix flake.lock
git commit -m "nix: add microvm.nix flake input"
```

---

### Task 2: Create the microVM guest configuration

**Files:**
- Create: `nix/modules/microvm.nix`

- [ ] **Step 1: Create the guest NixOS module**

Create `nix/modules/microvm.nix` with the full guest VM configuration:

```nix
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
```

- [ ] **Step 2: Verify the file parses**

Run: `nix eval --expr 'builtins.readFile ./nix/modules/microvm.nix' --raw | head -1`

Expected: First line of the file printed, no parse errors.

- [ ] **Step 3: Commit**

```bash
git add nix/modules/microvm.nix
git commit -m "nix: add microVM guest configuration"
```

---

### Task 3: Wire the microVM into flake.nix outputs

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Add nixosConfigurations.microvm and packages.microvm**

In the `outputs` `let` block of `flake.nix` (after the existing package definitions), add:

```nix
      # MicroVM NixOS configuration
      microvmConfig = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          microvm.nixosModules.microvm
          self.nixosModules.default
          ./nix/modules/microvm.nix
        ];
      };
```

Then add to the outputs (inside the `in { ... }` block):

After `packages.${system}`:
```nix
      # Add to the existing packages set:
      #   microvm = microvmConfig.config.microvm.declaredRunner;
```

Actually, modify the existing `packages.${system}` set to include:

```nix
        microvm = microvmConfig.config.microvm.declaredRunner;
```

And add a new top-level output:

```nix
      nixosConfigurations.microvm = microvmConfig;
```

- [ ] **Step 2: Evaluate the microVM configuration**

Run: `nix eval .#nixosConfigurations.microvm.config.microvm.hypervisor`

Expected: `"firecracker"`

- [ ] **Step 3: Build the microVM runner**

Run: `nix build .#microvm`

Expected: Build succeeds. `result/` contains the Firecracker runner script.

This build will take a while the first time (downloads PostgreSQL, Redis, Python, etc.).

- [ ] **Step 4: Commit**

```bash
git add flake.nix
git commit -m "nix: expose microVM as package and nixosConfiguration"
```

---

### Task 4: Create the host-side module

**Files:**
- Create: `nix/modules/microvm-host.nix`

- [ ] **Step 1: Create the host module**

Create `nix/modules/microvm-host.nix`. This is what missionctrl-infra will import to run the aweb microVM on the scape host:

```nix
# nix/modules/microvm-host.nix
#
# Host-side NixOS module for running the aweb microVM.
# Import this in the host machine's NixOS configuration.
#
# Usage (in missionctrl-infra):
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
```

- [ ] **Step 2: Export the host module from flake.nix**

Add to the outputs in `flake.nix`:

```nix
      nixosModules.microvm = { lib, ... }: {
        imports = [ ./nix/modules/microvm-host.nix ];
        services.aweb-vm.package = lib.mkDefault microvmConfig.config.microvm.declaredRunner;
      };
```

This sits alongside the existing `nixosModules.default`.

- [ ] **Step 3: Evaluate the host module**

Run: `nix eval .#nixosModules.microvm --apply 'x: builtins.typeOf x'`

Expected: `"lambda"` (it's a NixOS module function)

- [ ] **Step 4: Commit**

```bash
git add nix/modules/microvm-host.nix flake.nix
git commit -m "nix: add host-side microVM module for missionctrl-infra"
```

---

### Task 5: Verify the full build

**Files:**
- None (verification only)

- [ ] **Step 1: Build the microVM package**

Run: `nix build .#microvm`

Expected: Build succeeds. `result/bin/microvm-run` exists.

- [ ] **Step 2: Inspect the runner contents**

Run: `ls -la result/bin/`

Expected: Contains `microvm-run`, `microvm-shutdown`, and possibly other helper scripts.

- [ ] **Step 3: Verify existing checks still pass**

Run: `nix flake check --no-build`

Expected: No evaluation errors. All existing checks and the new microvm configuration evaluate cleanly.

- [ ] **Step 4: Verify the microVM config has the right services**

Run:
```bash
nix eval .#nixosConfigurations.microvm.config.systemd.services --apply 'x: builtins.attrNames x' --json | python3 -m json.tool | grep -E "aweb|awid|redis|postgres"
```

Expected: Output includes `aweb`, `awid`, `redis`, and `postgresql`.

- [ ] **Step 5: Verify networking config**

Run:
```bash
nix eval .#nixosConfigurations.microvm.config.systemd.network.networks --apply 'x: builtins.attrNames x' --json
```

Expected: Contains `"10-eth"`.

---

### Task 6: Integration smoke test (manual, on scape host)

This task is for manual verification after deploying to the scape host. It cannot be run locally unless you have a Firecracker-capable environment.

**Files:**
- None (manual verification)

- [ ] **Step 1: Build and transfer to scape host**

```bash
nix build .#microvm
nix copy --to ssh://scape .#microvm
```

- [ ] **Step 2: Run the microVM manually on scape**

SSH into scape and run the microVM in a temporary directory:

```bash
ssh scape
mkdir -p /tmp/aweb-vm-test && cd /tmp/aweb-vm-test
/nix/store/.../bin/microvm-run
```

Note: This requires the TAP device and bridge to exist. For a quick test without the host module, use the `qemu` hypervisor instead of firecracker by temporarily changing `microvm.hypervisor` in `microvm.nix`.

- [ ] **Step 3: Test health endpoints from the host**

From the scape host (or another VM on the bridge):

```bash
curl -sf http://10.99.0.2:8010/health && echo "awid OK"
curl -sf http://10.99.0.2:8000/health && echo "aweb OK"
```

Expected: Both return 200.

- [ ] **Step 4: Test aw init from an agent VM**

From a running claude-code or zeroclaw VM:

```bash
aw init --aweb-url http://10.99.0.2:8000 --awid-registry http://10.99.0.2:8010
```

Expected: Workspace connects successfully.
