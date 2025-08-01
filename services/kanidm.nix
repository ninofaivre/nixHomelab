# TODO PR to use systemd-creds instead of bindReadOnlyPaths for provision secret files ???
{ domain, root, dataDir }:
{ config, pkgs, ... }:
let
  scheme = "https";
in
{
  nixBind.bindings."127.0.0.1".tcp."kanidm" = 8443;
  services.kanidm = 
  let
    origin = "${scheme}://${domain}";
  in
  {
    package = pkgs.kanidmWithSecretProvisioning;
    enableClient = true;
    clientSettings.uri = origin;
    enableServer = true;
    provision = {
      enable = true;
      adminPasswordFile = config.sops.secrets."kanidm/accounts/admin".path;
      idmAdminPasswordFile = config.sops.secrets."kanidm/accounts/idmAdmin".path;
      persons = {
        services_admin = {
          displayName = "admin";
          mailAddresses = [ "admin@hl.6e696e6f.dev" ];
        };
      };
    };
    serverSettings = {
      domain = root.domain;
      inherit origin;
      trust_x_forward_for = true;
      bindaddress = config.nixBind.getAddressWithPort "127.0.0.1" "tcp" "kanidm";
      # TODO investigate why this option is read-only
      #db_path = "${dataDir}/kanidm.db";
      tls_chain = "${dataDir}/fullchain.pem";
      tls_key = "${dataDir}/key.pem";
    };
  };
}
