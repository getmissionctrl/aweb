# aweb Server MicroVM

A self-contained Firecracker microVM that runs the full aweb coordination
stack (aweb server, awid identity service, PostgreSQL, Redis). Deployed as a
NixOS service on the scape host so that scape-managed agent VMs can
coordinate through it over the bridge network.

## Context

The scape host (Hetzner dedicated, NixOS, 128 GB RAM) already runs:

- Scape orchestrator managing agent microVMs on bridge `scape-br0` (10.99.0.0/24)
- NATS for agent-orchestrator communication
- PostgreSQL for the scape console
- Caddy reverse proxy

Agent VMs (claude-code, zeroclaw) need an aweb server to coordinate. Rather
than adding aweb's dependencies (its own Postgres DB, Redis, Python services)
directly to the host, we run aweb in its own microVM for isolation. The VM
gets a static IP on the scape bridge so all agent VMs can reach it.

## Architecture

```
scape host (37.27.59.94)
├── scape-orchestrator
├── scape-br0 (10.99.0.0/24)
│   ├── 10.99.0.1  — host (gateway, NATS, Caddy)
│   ├── 10.99.0.2  — aweb microVM (this spec)
│   │   ├── aweb server   :8000
│   │   ├── awid service  :8010
│   │   ├── PostgreSQL     :5432 (internal)
│   │   └── Redis          :6379 (internal)
│   ├── 10.99.0.11+ — agent VMs (DHCP pool)
│   └── ...
```

Agent VMs reach aweb at `http://10.99.0.2:8000` and awid at
`http://10.99.0.2:8010`.

## Scope

This spec covers only the microVM definition and NixOS module in the aweb
repo. Three related but separate pieces of work are out of scope:

- Adding `aw` CLI + channel to scape-templates (claude-code, zeroclaw templates)
- Adding aweb as a flake input to missionctrl-infra and wiring it into the scape host config
- Caddy vhost for external HTTPS access (e.g., `aweb.missionctrl.dev`)

## MicroVM Definition

A new NixOS module at `nix/modules/microvm.nix` that defines the microVM
using the microvm.nix library. The aweb flake gains a `microvm` input and
exposes a new `nixosConfigurations.microvm` and `packages.x86_64-linux.microvm`.

### Guest Configuration

The VM runs four services:

1. **PostgreSQL 16** — Two databases: `aweb` (coordination state) and `awid`
   (identity registry). Peer auth with dedicated system users.
2. **Redis** — Single instance on localhost for aweb pub/sub events.
3. **awid** — Identity registry service. Binds `0.0.0.0:8010`.
4. **aweb** — Coordination server. Binds `0.0.0.0:8000`. Depends on awid.

All four are systemd services using the existing `services.aweb` NixOS module
from `nix/modules/aweb.nix`, plus standard nixpkgs PostgreSQL and Redis modules.

### Networking

- Single TAP interface on the scape bridge
- Static IP: `10.99.0.2/24`, gateway `10.99.0.1`
- Firewall disabled inside the VM (host firewall + bridge isolation is sufficient)
- aweb and awid bind `0.0.0.0` so agent VMs on the bridge can reach them

### Resources

- 2 vCPUs
- 2048 MB RAM
- Persistent ext4 volume for PostgreSQL data (`/var/lib/postgresql`)

### Storage

The microVM uses erofs for the root filesystem (read-only, compressed). A
persistent ext4 volume provides `/var/lib/postgresql` so database state
survives VM restarts. Redis data does not need persistence (it's pub/sub only,
no durable state).

## Flake Changes

```nix
# New input
inputs.microvm.url = "github:microvm-nix/microvm.nix";
inputs.microvm.inputs.nixpkgs.follows = "nixpkgs";

# New outputs
nixosConfigurations.microvm = ...;           # The VM NixOS config
packages.x86_64-linux.microvm = ...;         # declaredRunner
nixosModules.microvm = ...;                  # For host-side import
```

The `nixosModules.microvm` module is what missionctrl-infra imports. It
defines the host-side systemd service, TAP device, and bridge membership
using microvm.nix's host module pattern.

## File Layout

```
nix/
  modules/
    aweb.nix          # (existing) aweb + awid systemd services
    default.nix       # (existing) module entrypoint
    microvm.nix       # (new) microVM guest NixOS configuration
    microvm-host.nix  # (new) host-side module for importing into missionctrl-infra
  tests/
    default.nix       # (existing) NixOS test
```

## Host Integration (missionctrl-infra, out of scope but documented)

The scape host config will eventually add:

```nix
# In missionctrl-infra flake.nix inputs:
aweb.url = "github:awebai/aweb";

# In nix/scape/default.nix:
imports = [ inputs.aweb.nixosModules.microvm ];
```

This creates the TAP device, bridge membership, and systemd service for the
aweb microVM on the host. The static IP and bridge config are defined in the
microvm-host.nix module.

## Security

- PostgreSQL and Redis listen only on localhost inside the VM. They are not
  reachable from the bridge.
- aweb and awid listen on 0.0.0.0 but only ports 8000 and 8010 are useful.
- The VM has no SSH server (unlike agent templates). Debug access is via
  `microvm -c` console from the host.
- Agent VMs authenticate to aweb using team certificates, same as any aweb
  client.

## Success Criteria

1. `nix build .#microvm` produces a runnable Firecracker VM image
2. The VM boots, starts PostgreSQL, Redis, awid, and aweb in order
3. `curl http://10.99.0.2:8000/health` and `curl http://10.99.0.2:8010/health`
   return 200 from another VM on the bridge
4. An agent VM can run `aw init --aweb-url http://10.99.0.2:8000` and
   successfully connect
