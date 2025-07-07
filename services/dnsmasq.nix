{ servicesConfig, logFifoPath }:
{ config, pkgs, networking, ... }:
let
  fifoScript = pkgs.writeShellScript "pre-start" ''
    if [ ! -p ${logFifoPath} ]; then
      rm -f ${logFifoPath}
      mkfifo -m 664 ${logFifoPath}
    fi
  '';
in
{
  nixBind.bindings = {
    "${networking.interfaces.upLink.ips.lan.address}" = {
      udp."dnsmasq" = 53;
      tcp."dnsmasq" = 53;
    };
    "127.0.0.1" = {
      udp."dnsmasq" = 53;
      tcp."dnsmasq" = 53;
    };
  };
  systemd.services.dnsmasq = {
    after = [ "systemd-networkd-wait-online.service" ];
    serviceConfig = {
      RuntimeDirectory = "dnsmasq";
      ExecStartPre = fifoScript;
    };
  };
  services.dnsmasq.enable = true;
  services.dnsmasq.settings = {
    log-queries = "extra";
    log-facility = logFifoPath;
    bind-interfaces = true;
    listen-address = [ "127.0.0.1" networking.interfaces.upLink.ips.lan.address ];
    port = config.nixBind.bindings.${networking.interfaces.upLink.ips.lan.address}.udp.dnsmasq;
    server = [ "1.1.1.1" "1.0.0.1" "8.8.8.8" ];
    address = map ({ domain, ... }:
      "/${domain}/${networking.interfaces.upLink.ips.lanLocalDns.address}"
    ) (builtins.filter (el: el.domain != null) (builtins.attrValues servicesConfig));
    nftset = builtins.concatMap (el: el.target.dnsmasq) ((builtins.attrValues config.nftablesService.trackedDomains.http) ++ (builtins.attrValues config.nftablesService.trackedDomains.https));
  };
}
