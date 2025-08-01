# TODO PR to remove asyncitterator warning in logs (ref: paperless doc or dockerfile or service or s6)
# TODO setupd admin group via something like PAPERLESS_SOCIAL_ACCOUNT_ADMIN_GROUPS when the feature
# gets implemented or mb do a PR myself (https://github.com/paperless-ngx/paperless-ngx/discussions/9250)
{ domain, dataDir, kanidm }:
{ config, lib, ... }:
let
  scheme = "https";
  scopeMap = [ "email" "groups" "openid" "profile" ];
  paperlessKanidmProviderId = "kanidm";
  kanidmPaperlessOauthName = "paperless-ngx";
  # Local patch while waiting for a solution upstream ([see](https://github.com/NixOS/nixpkgs/pull/388414))
  cfg = config.services.paperless;
  isDbLocal = !(cfg.settings ? PAPELESS_DBHOST) || (lib.hasPrefix "/" cfg.settings.PAPERLESS_DBHOST);
in
{
  imports = [
    (import ./paperless-web-script-patch-allauth-secret.nix {
      providers = {
        openid_connect = {
          OAUTH_PKCE_ENABLED = true;
          SCOPE = scopeMap;
          APPS = [{
            provider_id = paperlessKanidmProviderId;
            name = "Kanidm";
            client_id = kanidmPaperlessOauthName;
            secretFile = config.sops.secrets."kanidm/systems/oauth2/paperless".path;
            settings.server_url = "${scheme}://${kanidm.domain}/oauth2/openid/${kanidmPaperlessOauthName}/.well-known/openid-configuration";
          }];
        };
      };
    })
  ];
  nftablesService.services = {
    "paperless-web".chains = { "out" = "accept"; "in" = "accept"; }; # empty out/in to enable default fw
  };
  /*
  systemd.services = builtins.foldl' (acc: el:
    acc // {
      "${el}".serviceConfig = {
         TemporaryFileSystem = "/data";
         BindPaths = dataDir;
       };
    }
  ) {} [ "paperless-scheduler" "paperless-task-queue" "paperless-consumer" "paperless-web" "paperless-exporter" ];
  */

  systemd.services.paperless-scheduler.serviceConfig.PrivateNetwork = lib.mkForce isDbLocal;
  systemd.services.paperless-consumer.serviceConfig.PrivateNetwork = lib.mkForce isDbLocal;
  
  nixBind.bindings."${config.services.paperless.address}".tcp."paperless" = config.services.paperless.port;
  services.paperless = {
    enable = true;
    address = "127.0.0.1";
    inherit dataDir;
    settings = {
      PAPERLESS_URL = "${scheme}://${domain}";
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
      PAPERLESS_SOCIAL_AUTO_SIGNUP = true;
      PAPERLESS_DISABLE_REGULAR_LOGIN = true;
      PAPERLESS_REDIRECT_LOGIN_TO_SSO = true;
      PAPERLESS_FILENAME_FORMAT = "{{ created_year }}/{{ correspondant }}/{{ created_day }}-{{ created_month }}_{{ title }}";
      PAPERLESS_SOCIAL_ACCOUNT_SYNC_GROUPS = true;
    };
  };
  services.kanidm.provision = let
    accessGroupName = "${kanidmPaperlessOauthName}-access";
    adminGroupName = "${kanidmPaperlessOauthName}-admin";
  in {
    groups."${accessGroupName}" = {
      members = [ adminGroupName ];
      overwriteMembers = false;
    };
    groups."${adminGroupName}" = {
      members = [ "services_admin" ];
      overwriteMembers = false;
    };
    systems.oauth2."${kanidmPaperlessOauthName}" = {
      displayName = "Paperless";
      originUrl = "${scheme}://${domain}/accounts/oidc/${paperlessKanidmProviderId}/login/callback/";
      originLanding = "${scheme}://${domain}/";
      basicSecretFile = config.sops.secrets."kanidm/systems/oauth2/paperless".path;
      scopeMaps."${accessGroupName}" = scopeMap;
    };
  };
}
