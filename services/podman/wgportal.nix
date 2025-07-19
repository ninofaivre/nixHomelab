# Auto-generated using compose2nix v0.3.1.
{ domain, dataDir, displayName }:
{ config, pkgs, lib, ... }:
let
  kanidmWgportalOauthName = "wgportal";
  wgportalKanidmProviderId = "kanidm";
  adminGroupName = "${kanidmWgportalOauthName}-admin";
  scopeMap = [ "profile" "email" "openid" "groups" ];
  kanidmSecretEnvVarName = "KANIDM_OAUTH2_SECRET";
  sessionSecretEnvVarName = "SESSION_SECRET";
  csrfSecretEnvVarName = "CSRF_SECRET";
  wgportalConfig = {
    web = {
      listening_address = "127.0.0.1:8888";
      external_url = "https://${domain}";
      site_company_name = "6e696e6f Homelab WireGuard Portal";
      site_title = displayName;
      session_identifier = "wgPortalSession";
      session_secret = ''''${${sessionSecretEnvVarName}}'';
      csrf_secret = ''''${${csrfSecretEnvVarName}}'';
      request_logging = false;
    };
    auth.oidc = [{
      provider_name = "kanidm";
      display_name = "Kanidm";
      base_url = "https://kanidm.hl.6e696e6f.dev/oauth2/openid/${kanidmWgportalOauthName}";
      client_id = kanidmWgportalOauthName;
      client_secret = ''''${${kanidmSecretEnvVarName}}'';
      log_user_info = true;
      registration_enabled = true;
      extra_scopes = scopeMap;
      field_map = {
        user_identifier = "preferred_username";
        user_groups = "groups";
        firstname = "name";
      };
      admin_mapping.admin_group_regex = "${adminGroupName}@hl.6e696e6f.dev";
    }];
  };
in
{
  services.kanidm.provision = let
    accessGroupName = "${kanidmWgportalOauthName}-access";
  in {
    # TODO wait or do a PR so groups can be declared empty and not overwritten so
    # I can imperatively add members to the group. (see https://github.com/oddlama/kanidm-provision/issues)"
    /*
    groups."${accessGroupName}" = {
      members = [ adminGroupName ];
    };
    */
    groups."${adminGroupName}" = {};
    persons.services_admin.groups = [ adminGroupName ];
    systems.oauth2."${kanidmWgportalOauthName}" = {
      inherit displayName;
      originUrl = "https://${domain}/";
      originLanding = "https://${domain}/api/v0/auth/login/${wgportalKanidmProviderId}/callback";
      basicSecretFile = config.sops.secrets."kanidm/systems/oauth2/wgportal".path;
      # TODO figure out why pkce is not working with wgportal and mb do a PR
      allowInsecureClientDisablePkce = true;
      scopeMaps."${accessGroupName}" = scopeMap;
    };
  };
  sops.templates."kanidm/systems/oauth2/wgportal.env".content = ''
    ${kanidmSecretEnvVarName}=${config.sops.placeholder."kanidm/systems/oauth2/wgportal"}
    ${sessionSecretEnvVarName}=${config.sops.placeholder."wgportal/web/session"}
    ${csrfSecretEnvVarName}=${config.sops.placeholder."wgportal/web/csrf"}
  '';
  nixBind.bindings."127.0.0.1".tcp.wgportal = 8888;
  virtualisation.oci-containers.containers."wgportal" = {
    image = "wgportal/wg-portal:v2";
    environmentFiles = [
      config.sops.templates."kanidm/systems/oauth2/wgportal.env".path
    ];
    volumes = [
      "${(pkgs.formats.yaml {}).generate "config.yml" wgportalConfig}:/app/config/config.yml:rw"
      "${dataDir}:/app/data:rw"
    ];
    ports = [
      "127.0.0.1:${toString config.nixBind.bindings."127.0.0.1".tcp.wgportal}:8888/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--network=host"
    ];
  };
  systemd.services."podman-wgportal" = {
    enable = false;
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    wantedBy = [
      "multi-user.target"
    ];
  };
}
