{ myUtils, lanIp, lanLocalDnsIp, ... }:
{
  imports = [
    (myUtils.uniqueIntStore [ "bindings" "127.0.0.1" ])
    (myUtils.uniqueIntStore [ "bindings" lanIp ])
    (myUtils.uniqueIntStore [ "bindings" lanLocalDnsIp ])
    ./traefik.nix
    ./paperless.nix
    ./caddy.nix
    ./dnsmasq.nix
    ./homepage-dashboard/homepage-dashboard.nix
  ];
}
