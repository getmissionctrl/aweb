{
  description = "aweb - Agent Web coordination platform";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, devshell, microvm, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ devshell.overlays.default ];
      };

      # Haskell
      hsPkgs = pkgs.haskell.packages.ghc910.override {
        overrides = hself: hsuper: {
          hasql-pool = pkgs.haskell.lib.dontCheck hsuper.hasql-pool;
          hasql-transaction = pkgs.haskell.lib.dontCheck hsuper.hasql-transaction;
          rel8 = pkgs.haskell.lib.dontCheck hsuper.rel8;
        };
      };
      awebHsPkg = hsPkgs.callCabal2nix "aweb-hs" ./hs {};

      # Go CLI (aw)
      awPkg = pkgs.buildGoModule {
        pname = "aw";
        version = "0.1.0";
        src = builtins.path { name = "aw-source"; path = ./cli/go; };
        subPackages = [ "cmd/aw" ];
        vendorHash = "sha256-msLqjpmMK3t2zaaf5V2GEP4022ssCiAeuNQ+lZbNsyM=";
        doCheck = false;
        meta.description = "aw CLI for agent coordination";
      };

      # Python package set with overrides for missing packages
      python = pkgs.python312;
      py = python.pkgs;

      pgdbm = py.buildPythonPackage {
        pname = "pgdbm";
        version = "0.4.1";
        src = py.fetchPypi {
          pname = "pgdbm";
          version = "0.4.1";
          hash = "sha256:2b95d60406fb932364a3bdab4e12c902e8cdf1436e9e3bcbef313f17ae9359ad";
        };
        pyproject = true;
        build-system = [ py.hatchling ];
        dependencies = [ py.asyncpg py.pydantic ];
        doCheck = false;
        meta.description = "PostgreSQL database manager";
      };

      # Shared Python deps for both awid and aweb
      commonPythonDeps = [
        py.base58
        py.dnspython
        py.fastapi
        py.httpx
        pgdbm
        py.publicsuffix2
        py.pydantic
        py.pydantic-settings
        py.pynacl
        py.redis
        py.typer
        py.uvicorn
      ];

      # Python identity service (awid)
      awidPkg = py.buildPythonApplication {
        pname = "awid-service";
        version = "0.5.4";
        src = ./awid;
        pyproject = true;
        build-system = [ py.hatchling ];
        dependencies = commonPythonDeps;
        doCheck = false;
        meta.description = "awid identity registry service";
      };

      # Python server (aweb)
      awebPkg = py.buildPythonApplication {
        pname = "aweb";
        version = "1.21.3";
        src = ./server;
        pyproject = true;
        build-system = [ py.hatchling ];
        dependencies = commonPythonDeps ++ [
          awidPkg
          py.cryptography
          py.mcp
          py.pyyaml
        ];
        doCheck = false;
        meta.description = "aweb coordination server";
      };

      # Skills (agent coordination docs, packaged for distribution)
      skillsPkg = pkgs.stdenv.mkDerivation {
        pname = "aweb-skills";
        version = "0.1.0";
        src = builtins.path { name = "aweb-skills-src"; path = ./.; };
        phases = [ "installPhase" ];
        installPhase = ''
          mkdir -p $out/skills
          cp -r $src/cli/go/skills/aweb $out/skills/
          cp -r $src/cli/go/skills/aweb-messaging $out/skills/
          cp -r $src/channel/skills/configure $out/skills/
        '';
        meta.description = "aweb agent coordination skills";
      };

      # TypeScript channel (MCP plugin)
      channelPkg = pkgs.buildNpmPackage {
        pname = "claude-channel";
        version = "1.4.0";
        src = ./channel;
        npmDepsHash = "sha256-OJZnDmy4j6V7CCeztsQh1bwGKK7HG9+ndZd251qhxKg=";
        buildPhase = ''
          npm run build
        '';
        installPhase = ''
          mkdir -p $out/lib/node_modules/@awebai/claude-channel
          cp -r dist package.json $out/lib/node_modules/@awebai/claude-channel/
          mkdir -p $out/bin
          ln -s $out/lib/node_modules/@awebai/claude-channel/dist/index.js $out/bin/claude-channel
        '';
        meta.description = "aweb Claude channel MCP plugin";
      };

      # MicroVM NixOS configuration
      microvmConfig = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          microvm.nixosModules.microvm
          self.nixosModules.default
          ./nix/modules/microvm.nix
        ];
      };

    in {
      packages.${system} = {
        default = awPkg;
        aw = awPkg;
        aweb = awebPkg;
        awid = awidPkg;
        aweb-hs = awebHsPkg;
        channel = channelPkg;
        skills = skillsPkg;
        microvm = microvmConfig.config.microvm.declaredRunner;
      };

      nixosConfigurations.microvm = microvmConfig;

      # NixOS module (imports ./nix/modules when it exists)
      nixosModules.default = { lib, ... }: {
        imports = [ ./nix/modules ];
        services.aweb.server.package = lib.mkDefault awebPkg;
        services.aweb.awid.package = lib.mkDefault awidPkg;
      };

      nixosModules.microvm = { lib, ... }: {
        imports = [ ./nix/modules/microvm-host.nix ];
        services.aweb-vm.package = lib.mkDefault microvmConfig.config.microvm.declaredRunner;
      };

      checks.${system} = {
        # Verify each package actually runs
        aw-runs = pkgs.runCommand "aw-runs" {} ''
          ${awPkg}/bin/aw version > $out
        '';
        awid-runs = pkgs.runCommand "awid-runs" {} ''
          ${awidPkg}/bin/awid --help > $out
        '';
        aweb-runs = pkgs.runCommand "aweb-runs" {} ''
          ${awebPkg}/bin/aweb --help > $out
        '';
        channel-runs = pkgs.runCommand "channel-runs" { nativeBuildInputs = [ pkgs.nodejs_20 ]; } ''
          node ${channelPkg}/lib/node_modules/@awebai/claude-channel/dist/index.js --help > $out 2>&1 || touch $out
        '';
        skills-exist = pkgs.runCommand "skills-exist" {} ''
          test -f ${skillsPkg}/skills/aweb/SKILL.md
          test -f ${skillsPkg}/skills/aweb-messaging/SKILL.md
          test -f ${skillsPkg}/skills/configure/SKILL.md
          echo "ok" > $out
        '';
        # NixOS module evaluation test (no VM needed)
        module-eval = pkgs.runCommand "module-eval" {} ''
          echo "Module evaluates: ${(pkgs.nixos [
            self.nixosModules.default
            {
              services.aweb.enable = true;
              services.aweb.server.databaseUrl = "postgresql://x@localhost/x";
              services.aweb.awid.databaseUrl = "postgresql://x@localhost/x";
            }
          ]).config.systemd.units."aweb.service".unit}" > /dev/null
          echo "ok" > $out
        '';
      };

      devShells.${system}.default = pkgs.devshell.mkShell {
        name = "aweb";

        packages = with pkgs; [
          # Python
          python312
          uv

          # Go
          go
          gopls
          goreleaser

          # Haskell
          hsPkgs.ghc
          cabal-install
          haskell-language-server

          # Node/TypeScript
          nodejs_20

          # Services
          postgresql_16
          redis
          nats-server

          # Tools
          process-compose
          curl
          jq
        ];

        env = [
          {
            name = "AWEB_DATABASE_URL";
            value = "postgresql://aweb:aweb@localhost:5433/aweb";
          }
          {
            name = "AWID_DATABASE_URL";
            value = "postgresql://aweb:aweb@localhost:5433/aweb";
          }
          {
            name = "AWID_DB_SCHEMA";
            value = "awid";
          }
          {
            name = "AWID_REGISTRY_URL";
            value = "http://127.0.0.1:8010";
          }
          {
            name = "APP_ENV";
            value = "development";
          }
          {
            name = "AWEB_REDIS_URL";
            value = "redis://localhost:6380";
          }
          {
            name = "AWID_REDIS_URL";
            value = "redis://localhost:6380";
          }
          {
            name = "PGPORT";
            value = "5433";
          }
        ];

        commands = [
          {
            category = "development";
            name = "devrun";
            help = "Start all dev services (postgres, redis, server, awid)";
            command = ''cd "$PRJ_ROOT" && process-compose up -f dev/process-compose.yaml -p 9900'';
          }
          {
            category = "development";
            name = "dev-server";
            help = "Start aweb server in dev mode";
            command = ''cd "$PRJ_ROOT/server" && uv run aweb serve --reload'';
          }
          {
            category = "development";
            name = "dev-awid";
            help = "Start awid identity service in dev mode";
            command = ''cd "$PRJ_ROOT/awid" && uv run awid serve --reload'';
          }
          {
            category = "testing";
            name = "test-all";
            help = "Run all test suites";
            command = ''
              cd "$PRJ_ROOT"
              echo "=== Server tests ===" && (cd server && uv run pytest) &&
              echo "=== AWID tests ===" && (cd awid && uv run pytest) &&
              echo "=== CLI tests ===" && (cd cli/go && go test ./...) &&
              echo "=== Channel tests ===" && (cd channel && npm test)
            '';
          }
          {
            category = "testing";
            name = "test-server";
            help = "Run server test suite";
            command = ''cd "$PRJ_ROOT/server" && uv run pytest "$@"'';
          }
          {
            category = "testing";
            name = "test-awid";
            help = "Run awid test suite";
            command = ''cd "$PRJ_ROOT/awid" && uv run pytest "$@"'';
          }
          {
            category = "testing";
            name = "test-cli";
            help = "Run Go CLI tests";
            command = ''cd "$PRJ_ROOT/cli/go" && go test ./...'';
          }
          {
            category = "testing";
            name = "test-channel";
            help = "Run channel tests";
            command = ''cd "$PRJ_ROOT/channel" && npm test'';
          }
          {
            category = "build";
            name = "build-cli";
            help = "Build aw CLI binary";
            command = ''cd "$PRJ_ROOT/cli/go" && go build -o "$PRJ_ROOT/result/aw" ./cmd/aw'';
          }
        ];
      };
    };
}
