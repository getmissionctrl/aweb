{ pkgs, self }:

pkgs.testers.nixosTest {
  name = "aweb-services";

  nodes.server = { ... }: {
    imports = [ self.nixosModules.default ];

    services.aweb = {
      enable = true;
      server.databaseUrl = "postgresql://aweb:aweb@127.0.0.1:5432/aweb";
      awid.databaseUrl = "postgresql://aweb:aweb@127.0.0.1:5432/aweb";
    };

    services.postgresql = {
      enable = true;
      ensureDatabases = [ "aweb" ];
      ensureUsers = [{
        name = "aweb";
        ensureDBOwnership = true;
      }];
      authentication = ''
        local all all trust
        host all all 127.0.0.1/32 trust
      '';
    };

    services.redis.servers."".enable = true;
  };

  testScript = ''
    server.wait_for_unit("postgresql.service")
    server.wait_for_unit("redis.service")
    server.wait_for_unit("awid.service")
    server.wait_for_unit("aweb.service")

    # Verify health endpoints respond
    server.wait_until_succeeds("curl -sf http://127.0.0.1:8010/health")
    server.wait_until_succeeds("curl -sf http://127.0.0.1:8000/health")
  '';
}
