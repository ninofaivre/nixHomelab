{ config, myUtils, lanIp, lanLocalDnsIp, ... }:
let
  dataDir = "/data/services/traefik";
  paperlessHostName = "paperless.hl.6e696e6f.dev";
  cloudflareTokenCredID = myUtils.assertions.isValidSystemdCredentialID "cloudflareDnsToken";
in
{
  nftablesService.services."traefik".chains = with config.networking.nftables.marks; {
    "out" = ''
      ip daddr ${config.services.paperless.address} tcp dport ${toString config.services.paperless.port} accept
      ip daddr localhost tcp dport { ${toString config.bindings."127.0.0.1"."caddyTest.hl"}, ${toString config.services.homepage-dashboard.listenPort} } accept
      #ip daddr 127.0.0.53 udp dport 53 accept
      #ip daddr 1.1.1.1 udp dport 53 accept
      #ip daddr 1.0.0.1 udp dport 53 accept
      meta l4proto { udp, tcp } th dport 53 accept
      tcp dport 443 ct zone != { ${toString ct.zones.local}, ${toString ct.zones.vpnServices} } accept
      log prefix "NFT traefik out drop :"
    '';
    "in" = ''
      ip daddr 127.0.0.1 tcp dport { 81,444 } ct zone { ${toString ct.zones.local}, ${toString ct.zones.vpnServices} } accept
      ip daddr ${lanIp} tcp dport { 80, 443 } accept
      ip daddr ${lanLocalDnsIp} tcp dport { 80, 443 } ct zone ${toString ct.zones.local} accept
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
    };
  };
  bindings = {
    "127.0.0.1" = {
      "traefikPrivateHttp" = 81;
      "traefikPrivateHttps" = 444;
    };
    "${lanIp}" = {
      "traefikPublicHttp" = 80;
      "traefikPublicHttps" = 443;
    };
    "${lanLocalDnsIp}" = {
      "traefikPrivateHttpLocalDns" = 80;
      "traefikPrivateHttpsLocalDns" = 443;
    };
  };
  services.traefik = 
  let
    inherit (config) bindings;
  in
  {
    enable = true;
    inherit dataDir;
    staticConfigOptions = {
      log = { level = "INFO"; };
      api = {
        dashboard = true;
        insecure = true;
      };
      entryPoints = {
        "publicHttp" = {
          address = "${lanIp}:${toString bindings.${lanIp}.traefikPublicHttp}";
          http.redirections.entryPoint = { scheme = "https"; to = "publicHttps"; };
        };
        "publicHttps".address = "${lanIp}:${toString bindings.${lanIp}.traefikPublicHttps}";

        "privateHttp" = {
          address = "localhost:${toString bindings."127.0.0.1".traefikPrivateHttp}";
          http.redirections.entryPoint = { scheme = "https"; to = "publicHttps"; };
        };
        "privateHttps" = {
          address = "localhost:${toString bindings."127.0.0.1".traefikPrivateHttps}";
          asDefault = true;
        };
        "privateHttpLocalDns" = {
          address = "${lanLocalDnsIp}:80";
          http.redirections.entryPoint = { scheme = "https"; to = "privateHttpsLocalDns"; };
        };
        "privateHttpsLocalDns" = {
          address = "${lanLocalDnsIp}:443";
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
            resolvers = [ "1.1.1.1:53" "1.0.0.1:53" ];
          };
        };
      };
    };
    dynamicConfigOptions = {
      http = {
        routers = {
          "paperless" = {
            rule = "Host(`${paperlessHostName}`)";
            service = "paperless";
            tls.certResolver = "cloudflare";
          };
          "homelab" = {
            rule = "Host(`hl.6e696e6f.dev`)";
            service = "noop@internal";
            middlewares = ["redirectionFromHlToHomepageDotHl"];
            tls.certResolver = "cloudflare";
          };
          "homepage" = {
            rule = "Host(`homepage.hl.6e696e6f.dev`)";
            service = "homepage";
            tls.certResolver = "cloudflare";
          };
          "testHomelabConnexionFromHome" = {
            rule = "Host(`test.hl.6e696e6f.dev`) && ClientIP(`192.168.1.0/24`)";
            service = "testHomelabConnexion";
            middlewares = ["testHomelabConnexionFromHome"];
            entryPoints = ["privateHttps"];
            tls.certResolver = "cloudflare";
          };
          "testHomelabConnexionFromHomeLocalDns" = {
            rule = "Host(`test.hl.6e696e6f.dev`) && ClientIP(`192.168.1.0/24`)";
            service = "testHomelabConnexion";
            middlewares = ["testHomelabConnexionFromHomeLocalDns"];
            entryPoints = ["privateHttpsLocalDns"];
            tls.certResolver = "cloudflare";
          };
          "testHomelabConnexionFromVpn" = {
            rule = "Host(`test.hl.6e696e6f.dev`) && ClientIP(`10.0.1.0/24`)";
            service = "testHomelabConnexion";
            middlewares = ["testHomelabConnexionFromVpn"];
            tls.certResolver = "cloudflare";
          };
        };
        middlewares = {
          "redirectionFromHlToHomepageDotHl".redirectRegex = {
            regex = "https://hl.6e696e6f.dev/(.*)";
            replacement = "https://homepage.hl.6e696e6f.dev/$1";
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
        services = {
          "paperless" = {
            loadBalancer.servers = [{
              url = "http://${config.services.paperless.address}:${toString config.services.paperless.port}";
            }];
          };
          "homepage" = {
            loadBalancer.servers = [{
              url = "http://127.0.0.1:${toString config.services.homepage-dashboard.listenPort}";
            }];
          };
          "testHomelabConnexion" = {
            loadBalancer.servers = [{
              url = "http://localhost:${toString bindings."127.0.0.1"."caddyTest.hl"}";
            }];
          };
        };
      };
    };
  };
}
