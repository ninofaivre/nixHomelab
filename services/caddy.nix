{ test }:
{ config, lib, ... }:
let
  dataDir = "/data/services/caddy";
in
{
  systemd.services.caddy.serviceConfig = {
    TemporaryFileSystem = "/data";
    BindPaths = dataDir;
  };

  nftablesService.services."caddy".chains = {
    "out" = ''
      ip daddr 127.0.0.1 tcp dport ${toString config.nixBind.bindings."127.0.0.1".tcp."caddyAdmin"} accept
    '';
    "in" = "";
  };

  nixBind.bindings."127.0.0.1"."tcp" = {
    "caddyTest.hl" = 80;
    "caddyAdmin" = 2019;
  };
  services.caddy = {
    enable = true;
    inherit dataDir;
    globalConfig = ''
      grace_period 1s
    '';
    virtualHosts = {
      "${test.domain}:${toString config.nixBind.bindings."127.0.0.1".tcp."caddyTest.hl"}" = {
        listenAddresses = [ "127.0.0.1" ];
        extraConfig = ''
          encode gzip

          header {
            Access-Control-Allow-Origin  *
            Access-Control-Allow-Methods  GET, POST, PUT, DELETE, OPTIONS
            Access-Control-Allow-Headers  Content-Type
          }

          respond /vpn "You are connected from VPN network and using global DNS !"
          respond /homeGlobalDns "You are connected from Home network and using global DNS !"
          respond /homeLocalDns "You are connected from Home network and using local DNS !"

          respond /api/vpn `{ "network": "vpn", "dns": "global" }`
          respond /api/homeGlobalDns `{ "network": "home", "dns": "global" }`
          respond /api/homeLocalDns `{ "network": "home", "dns": "local" }`
        '';
      };
    };
  };
}
