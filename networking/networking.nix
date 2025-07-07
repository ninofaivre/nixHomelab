{ networking, ... }:
{
  imports = [ ./firewall.nix ./wireguard.nix ];
  networking = {
    useNetworkd = true;
    useDHCP = false;
    nameservers = [
      "127.0.0.1"
      "1.1.1.1"
    ];
    hostName = "NixOsNas";
    hosts = {
      "${networking.interfaces.upLink.ips.lan.address}" = [ "lanMe" ];
    };
    defaultGateway = {
      interface = networking.interfaces.upLink.name;
      address = "192.168.1.254";
    };
    interfaces."${networking.interfaces.upLink.name}" = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = networking.interfaces.upLink.ips.lan.address;
          prefixLength = networking.interfaces.upLink.ips.lan.cidr;
        }
        {
          address = networking.interfaces.upLink.ips.lanLocalDns.address;
          prefixLength = networking.interfaces.upLink.ips.lanLocalDns.cidr;
        }
      ];
    };
    nat = {
      enable = true;
      externalInterface = networking.interfaces.upLink.name;
    };
  };
  services.resolved.enable = false;
}
