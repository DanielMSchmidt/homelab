{ pkgs, ... }:
{
  name = "caddy";

  nodes.machine = { pkgs, ... }: {
    imports = [ ../modules/caddy.nix ];

    # Dummy backend on port 8080 to proxy to
    systemd.services.dummy-backend = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        ${pkgs.python3}/bin/python3 -c "
        from http.server import HTTPServer, BaseHTTPRequestHandler
        class H(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'dummy-ok')
        HTTPServer(('127.0.0.1', 8080), H).serve_forever()
        "
      '';
    };

    # Override caddy config to proxy test.home.lan -> dummy backend
    services.caddy.virtualHosts."http://test.home.lan".extraConfig = ''
      reverse_proxy localhost:8080
    '';

    # Fake DNS: resolve test.home.lan to localhost
    networking.hosts."127.0.0.1" = [ "test.home.lan" ];
  };

  testScript = ''
    machine.wait_for_unit("caddy.service")
    machine.wait_for_unit("dummy-backend.service")
    machine.wait_for_open_port(80)

    # Caddy proxies based on Host header
    output = machine.succeed("curl -sf -H 'Host: test.home.lan' http://127.0.0.1")
    assert "dummy-ok" in output, f"Expected 'dummy-ok', got: {output}"
  '';
}
