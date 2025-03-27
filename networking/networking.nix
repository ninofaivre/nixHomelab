{ lib, upLink, lanIp, lanLocalDnsIp, ... }:
{
  imports = [ ./firewall.nix ./wireguard.nix ];
  networking = {
    useNetworkd = true;
    useDHCP = false;
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "192.168.1.254"
    ];
    hostName = "NixOsNas";
    hosts = {
      "${lanIp}" = [ "lanMe" ];
    };
    defaultGateway = {
      interface = upLink;
      address = "192.168.1.254";
    };
    interfaces."${upLink}" = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = lanIp;
          prefixLength = 24;
        }
        {
          address = lanLocalDnsIp;
          prefixLength = 24;
        }
      ];
    };
    nat = {
      enable = true;
      externalInterface = upLink;
    };
  };
}
