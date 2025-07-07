{ config, networking, ... }:
let
  serverListenPort = 51820;
  inherit (networking.interfaces) vpnServer;
in
{
  nixBind.bindings."0.0.0.0".udp."wireguardServer" = serverListenPort;
  networking.wireguard.enable = true;
  networking.wireguard.interfaces."${vpnServer.name}" = {
    privateKeyFile = config.sops.secrets.wireguardPrivateKey.path;
    listenPort = serverListenPort;
    ips = map (el: el.cidrAddress) (builtins.attrValues vpnServer.ips);
    peers = [
      {
        name = "nino";
        publicKey = "NaEVewAix3vFcZMoekXKmYuKMp6sTfsESv2x1jBBOFc=";
        allowedIPs = [
          "10.0.1.2/32"
          "10.0.2.2/32"
        ];
      }
    ];
  };
}
