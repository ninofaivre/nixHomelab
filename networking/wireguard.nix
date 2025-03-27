{ config, lanIp, ... }:
let
  hlServicesIp = "10.0.1.1/24";
in
{
  bindings."${lanIp}"."wireguardWg0" = config.networking.wireguard.interfaces."wg0".listenPort;
  networking.wireguard.enable = true;
  networking.wireguard.interfaces."wg0" = {
    privateKeyFile = config.sops.secrets.wireguardPrivateKey.path;
    listenPort = 51820;
    ips = [
      hlServicesIp
      "10.0.2.1/24"
    ];
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
