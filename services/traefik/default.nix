{ servicesConfig, staging }:
{ config, pkgs, myUtils, networking, ... }:
let
  dataDir = "/data/services/traefik";
  cloudflareTokenCredID = myUtils.assertions.isValidSystemdCredentialID "cloudflareDnsToken";
in
{
  imports = [ (import ./fw.nix { inherit staging; }) ];
  systemd.services.traefik = {
    environment = {
      "CF_DNS_API_TOKEN_FILE" = "%d/${cloudflareTokenCredID}";
    };
    serviceConfig = {
      LoadCredential = [
        "${cloudflareTokenCredID}:${config.sops.secrets.cloudflareDnsToken.path}"
      ];
      TemporaryFileSystem = "/data";
      BindPaths = dataDir;
      BindReadOnlyPaths = "${pkgs.writeText "hosts" ''
        127.0.0.1 ${servicesConfig.kanidm.domain}
      ''
      }:/etc/hosts:norbind";
    };
  };
  nixBind.bindings = {
    "127.0.0.1".tcp = {
      "traefikPrivateHttp" = 81;
      "traefikPrivateHttps" = 444;
    };
    "${networking.interfaces.upLink.ips.lan.address}".tcp = {
      "traefikPublicHttp" = 80;
      "traefikPublicHttps" = 443;
    };
    "${networking.interfaces.upLink.ips.lanLocalDns.address}".tcp = {
      "traefikPrivateHttpLocalDns" = 80;
      "traefikPrivateHttpsLocalDns" = 443;
    };
  };
  services.traefik = {
    enable = true;
    inherit dataDir;
    staticConfigOptions = {
      log = { level = "ERROR"; };
      accessLog = {};
      api = {
        dashboard = false;
        insecure = false;
      };
      entryPoints = 
      with config.nixBind;
      with networking.interfaces.upLink.ips;
      {
        "publicHttp" = {
          address = getAddressWithPort lan.address "tcp" "traefikPublicHttp";
          http.redirections.entryPoint = { scheme = "https"; to = "publicHttps"; };
        };
        "publicHttps" = {
          address = getAddressWithPort lan.address "tcp" "traefikPublicHttps";
        };
        "privateHttp" = {
          address = getAddressWithPort "127.0.0.1" "tcp" "traefikPrivateHttp";
          http.redirections.entryPoint = { scheme = "https"; to = "publicHttps"; };
        };
        "privateHttps" = {
          address = getAddressWithPort "127.0.0.1" "tcp" "traefikPrivateHttps";
          asDefault = true;
        };
        "privateHttpLocalDns" = {
          address = getAddressWithPort lanLocalDns.address "tcp" "traefikPrivateHttpLocalDns";
          http.redirections.entryPoint = { scheme = "https"; to = "privateHttpsLocalDns"; };
        };
        "privateHttpsLocalDns" = {
          address = getAddressWithPort lanLocalDns.address "tcp" "traefikPrivateHttpsLocalDns";
          asDefault = true;
        };
      };
      certificatesResolvers = {
        "cloudflare".acme = {
          email = "admin@6e696e6f.dev";
          storage = "${dataDir}/acme${if staging then "-staging" else ""}.json";
          caServer = "https://acme${if staging then "-staging" else ""}-v02.api.letsencrypt.org/directory";
          dnsChallenge = {
            provider = "cloudflare";
            delayBeforeCheck = 60;
            # prefer to not use local resolver to check for dns propagation
            # /!\ only use ip (no domain name) in there /!\
            resolvers = [ "1.1.1.1:53" "1.0.0.1:53" ];
          };
        };
      };
    };
    dynamicConfigOptions =
      with networking.interfaces;
    {
      http = {
        routers = {
          "paperless" = {
            rule = "Host(`${servicesConfig.paperless.domain}`)";
            service = "paperless";
            tls.certResolver = "cloudflare";
          };
          "wgportal" = {
            rule = "Host(`${servicesConfig.wgportal.domain}`)";
            service = "wgportal";
            tls.certResolver = "cloudflare";
          };
          "homelab" = {
            rule = "Host(`${servicesConfig.root.domain}`)";
            service = "noop@internal";
            middlewares = ["redirectionFromHlToHomepageDotHl"];
            tls.certResolver = "cloudflare";
          };
          "homepage" = {
            rule = "Host(`${servicesConfig.homepage-dashboard.domain}`)";
            service = "homepage";
            tls.certResolver = "cloudflare";
          };
          "kanidm" = {
            rule = "Host(`${servicesConfig.kanidm.domain}`)";
            service = "kanidm";
            tls.certResolver = "cloudflare";
          };
          "testHomelabConnexionFromHome" = {
            rule = "Host(`${servicesConfig.test.domain}`) && ClientIP(`${upLink.ips.lan.cidrAddress}`)";
            service = "testHomelabConnexion";
            middlewares = ["testHomelabConnexionFromHome"];
            entryPoints = ["privateHttps"];
            tls.certResolver = "cloudflare";
          };
          "testHomelabConnexionFromHomeLocalDns" = {
            rule = "Host(`${servicesConfig.test.domain}`) && ClientIP(`${upLink.ips.lan.cidrAddress}`)";
            service = "testHomelabConnexion";
            middlewares = ["testHomelabConnexionFromHomeLocalDns"];
            entryPoints = ["privateHttpsLocalDns"];
            tls.certResolver = "cloudflare";
          };
          "testHomelabConnexionFromVpn" = {
            rule = "Host(`${servicesConfig.test.domain}`) && ClientIP(`${vpnServer.ips.privateServices.cidrAddress}`)";
            service = "testHomelabConnexion";
            middlewares = ["testHomelabConnexionFromVpn"];
            tls.certResolver = "cloudflare";
          };
        };
        middlewares = {
          "redirectionFromHlToHomepageDotHl".redirectRegex = {
            regex = "https://${servicesConfig.root.domain}/(.*)";
            replacement = "https://${servicesConfig.homepage-dashboard.domain}/$1";
            permanent = true;
          };
          "testHomelabConnexionFromHome".replacePathRegex = {
            regex = "(.*)";
            replacement = "/$1/homeGlobalDns";
          };
          "testHomelabConnexionFromHomeLocalDns".replacePathRegex = {
            regex = "(.*)";
            replacement = "/$1/homeLocalDns";
          };
          "testHomelabConnexionFromVpn".replacePathRegex = {
            regex = "(.*)";
            replacement = "/$1/vpn";
          };
        };
        services =
          with config.nixBind;
        {
          "paperless".loadBalancer.servers = [{
            url = "http://${getAddressWithPort "127.0.0.1" "tcp" "paperless"}";
          }];
          "wgportal".loadBalancer.servers = [{
            url = "http://${getAddressWithPort "127.0.0.1" "tcp" "wgportal"}";
          }];
          "kanidm".loadBalancer.servers = [{
            url = "https://${servicesConfig.kanidm.domain}:${toString bindings."127.0.0.1".tcp."kanidm"}";
          }];
          "homepage".loadBalancer.servers = [{
            url = "http://${getAddressWithPort "127.0.0.1" "tcp" "homepage"}";
          }];
          "testHomelabConnexion".loadBalancer.servers = [{
            url = "http://${getAddressWithPort "127.0.0.1" "tcp" "caddyTest.hl"}";
          }];
        };
      };
    };
  };
}
