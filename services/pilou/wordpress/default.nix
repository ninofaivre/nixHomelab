{ config, pkgs, ... }:
let
  getWordpressOrgPlugin = { name, version, hash }:
    pkgs.stdenv.mkDerivation {
      inherit name version;
      src = pkgs.fetchzip {
        url = "https://downloads.wordpress.org/plugins/${name}.${version}.zip";
        inherit hash;
      };
      installPhase = "mkdir -p $out; cp -R * $out/";
    };
in
{
  nixBind.bindings = {
    "127.0.0.1".tcp = {
      "wordpressAlpha" = 82;
      "wordpressCommandCenter" = 83;
    };
  };
  services.httpd.extraConfig = ''
    SetEnvIf X-Forwarded-Proto "https" HTTPS=on
  '';
  services.wordpress = let
    inherit (config.nixBind) bindings;
    openidConnectServerPlugin = getWordpressOrgPlugin {
      name = "openid-connect-server";
      version = "2.0.0";
      hash = "sha256-RBRihh2RPX44lUkRASiSh86c0kCPRwuOIRMSYzvrqeM=";
    };
  in {
    webserver = "httpd";
    sites = {
      # Bravo, Charlie, Delta
      alpha = {
        settings = {
          WP_SITEURL = "https://alpha.wordpress.pilou.hl.6e696e6f.dev";
          WP_HOME = "https://alpha.wordpress.pilou.hl.6e696e6f.dev";
        };
        plugins = {
          inherit openidConnectServerPlugin;
        };
        virtualHost = {
          listen = [{
            ip = "127.0.0.1";
            port = bindings."127.0.0.1".tcp.wordpressAlpha;
          }];
        };
      };
    };
  };
}
