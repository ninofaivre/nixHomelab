{ config, lib, ... }:
{
  sops = {
    age.keyFile = "/home/nino/.config/sops/age/keys.txt";
    secrets = builtins.mapAttrs (name: value:
      if value ? sopsFile then
        value
      else value // (
        let
          serviceName = builtins.elemAt (lib.strings.splitString "/" name) 0;
        in {
          sopsFile = ./secrets + "/${serviceName}.yaml";
        }
      )
    ) {
      "cloudflareDnsToken" = {
        sopsFile = ./secrets/secrets.yaml;
        restartUnits = [ "traefik.service" ];
      };
      "paperlessAdminPassword" = {
        sopsFile = ./secrets/secrets.yaml;
        restartUnits = [ "system-paperless.slice" ];
      };
      "wireguardPrivateKey" = {
        sopsFile = ./secrets/secrets.yaml;
        restartUnits = [ "wireguard-wg0.service" ];
      };
      "wgportal/web/session" = {
        restartUnits = [ "podman-wgportal.service" ];
      };
      "wgportal/web/csrf" = {
        restartUnits = [ "podman-wgportal.service" ];
      };
      "kanidm/systems/oauth2/paperless" = {
        restartUnits = [ "kanidm.service" "system-paperless.slice" ];
      };
      "kanidm/systems/oauth2/wgportal" = {
        restartUnits = [ "kanidm.service" "podman-wgportal.service" ];
      };
      "kanidm/accounts/admin" = {
        restartUnits = [ "kanidm.service" ];
      };
      "kanidm/accounts/idmAdmin" = {
        restartUnits = [ "kanidm.service" ];
      };
    };
  };
}
