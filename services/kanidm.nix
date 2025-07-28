# TODO PR to use systemd-creds instead of bindReadOnlyPaths for provision secret files ???
{ domain, root, dataDir }:
{ lib, config, pkgs, ... }:
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
    package = pkgs.kanidm_1_5.withSecretProvisioning;
    enableClient = true;
    clientSettings.uri = origin;
    enableServer = true;
    provision = {
      enable = true;
      # TODO wait or do a PR so groups can be declared empty and not overwritten so
      # I can imperatively add members to the group. (see https://github.com/oddlama/kanidm-provision/issues)"
      # extraJsonFile disable some assertions for use of undeclared groups (which I'm forced
      # to create imperatively for now (<service-name>-access groups))
      extraJsonFile = builtins.toFile "empty.json" ''{}'';
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
