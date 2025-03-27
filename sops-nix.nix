{
  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    age.keyFile = "/home/nino/.config/sops/age/keys.txt";
    secrets."cloudflareDnsToken" = {
      restartUnits = [ "traefik.service" ];
    };
    secrets."paperlessAdminPassword" = {
      restartUnits = [ "system-paperless.slice" ];
    };
    secrets."wireguardPrivateKey" = {
      restartUnits = [ "wireguard-wg0" ];
    };
    # not needed but really cool and probably useful for others cases
    #templates."cloudflare_token.env" = {
    #  content = ''CF_DNS_API_TOKEN=${config.sops.placeholder."cloudflare_token"}'';
    #};
  };
}
