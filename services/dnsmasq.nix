{ config, lanIp, lanLocalDnsIp, ... }:
{
  services.dnsmasq.enable = true;
  services.dnsmasq.settings = {
    bind-interfaces = true;
    listen-address = [ lanIp ];
    server = [ "1.1.1.1" "1.0.0.1" ];
    address = [
      "/test.hl.6e696e6f.dev/${lanLocalDnsIp}"
      "/paperless.hl.6e696e6f.dev/${lanLocalDnsIp}"
      "/hl.6e696e6f.dev/${lanLocalDnsIp}"
      "/homepage.hl.6e696e6f.dev/${lanLocalDnsIp}"
    ];
  };
}
