{ servicesConfig }:
{ config, pkgs, myUtils, networking, ... }:
let
  dataDir = "/data/services/traefik";
  cloudflareTokenCredID = myUtils.assertions.isValidSystemdCredentialID "cloudflareDnsToken";
in
{
  nftablesService.services."traefik".chains =
    with config.networking.nftables.marks;
    with config.nixBind;
  {
    out = ''
      ${getNftTarget {
        address = "127.0.0.1";
        protocol = "tcp";
        ports = [ "caddyTest.hl" "homepage" "wgportal" "paperless" "kanidm" ];
      }} accept

      #ip daddr 127.0.0.53 udp dport 53 accept
      #ip daddr 1.1.1.1 udp dport 53 accept
      #ip daddr 1.0.0.1 udp dport 53 accept
      meta l4proto { udp, tcp } th dport 53 accept
      tcp dport 443 ct zone != { ${toString ct.zones.lan}, ${toString ct.zones.vpnServices} } accept
    '';
    "in" =
       with networking.interfaces.upLink.ips;
    ''
      ${getNftTarget {
        address = "127.0.0.1";
        protocol = "tcp";
        ports = [ "traefikPrivateHttp" "traefikPrivateHttps" ];
      }} ct zone { ${toString ct.zones.lan}, ${toString ct.zones.vpnServices} } accept
      ${getNftTarget {
        address = lan.address;
        protocol = "tcp";
        ports = [ "traefikPublicHttp" "traefikPublicHttps" ];
      }} accept
      ${getNftTarget {
        address = lanLocalDns.address;
        protocol = "tcp";
        ports = [ "traefikPrivateHttpLocalDns" "traefikPrivateHttpsLocalDns" ];
      }} ct zone ${toString ct.zones.lan} accept
    '';
  };
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
      log = { level = "DEBUG"; };
      accessLog = {};
      api = {
        dashboard = true;
        insecure = true;
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
          storage = "${dataDir}/acme.json";
          dnsChallenge = {
            provider = "cloudflare";
            delayBeforeCheck = 5;
            resolvers = [ "1.1.1.1:53" "1.0.0.1:53" ];# not local resolver to check propagation
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
