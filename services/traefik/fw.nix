{ staging }:
{ config, lib, myUtils, networking, ... }:
{
  nftablesService.trackDomains = [
    # traefik check for new version
    "update.traefik.io"
    "api.github.com"
    # acme dns challenge
    "acme-${if staging then "staging-" else ""}v02.api.letsencrypt.org"
    "api.cloudflare.com"
    "*.ns.cloudflare.com"
  ];
  nftablesService.services."traefik".chains = let
    inherit (config) nixBind;
    inherit (config.networking.nftables) marks;
  in {
    out = ''
      ${nixBind.getNftTargets {
        "127.0.0.1" = {
          protos = {
            tcp = [
              "caddyTest.hl"
              "homepage"
              "wgportal"
              "paperless"
              "kanidm"
              "knot-resolver"

              # Pilou #
              "wordpressAlpha"
              "wordpressCommandCenter"
            ];
            udp = [
              "knot-resolver"
            ];
          };
        };
      } "accept"}

      # acme propagation check resolvers
      ${let
          resolvers = config.services.traefik.staticConfigOptions.certificatesResolvers.cloudflare.acme.dnsChallenge.resolvers;
          portToAddrsAttr = builtins.foldl' (acc: resolver: let
              splittedResolver = lib.splitString ":" resolver;
              len = builtins.length splittedResolver;
              port = if len == 1 then
                  53
                else if len == 2 then
                  builtins.elemAt splittedResolver 1
                else
                  abort "TODO error message"
                ;
              address = builtins.elemAt splittedResolver 0;
            in acc // {
              ${port} = (acc.${port} or []) ++ [address];
            }) {} resolvers
          ;
        in
        lib.concatMapAttrsStringSep "" (port: addresses:
          "ip daddr ${myUtils.listToNftablesSet addresses} meta l4proto { udp, tcp } th dport ${port} accept"
        ) portToAddrsAttr
      }

      # acme dns challenge
      ${config.nftablesService.trackedDomains."*.ns.cloudflare.com".targets.nftables.get "meta l4proto { udp, tcp } th dport 53 ct state new accept"}

      ${config.nftablesService.getTargets.nftables [
          # traefik check for new version
          "update.traefik.io"
          "api.github.com"

          # acme dns challenge
          "acme-${if staging then "staging-" else ""}v02.api.letsencrypt.org"
          "api.cloudflare.com"
        ] "tcp dport 443 ct state new accept"
      }
    '';
    "in" = let
      inherit (networking.interfaces) upLink;
    in ''
      ${nixBind.getNftTargets {
        "127.0.0.1" = {
          protos.tcp = [ "traefikPrivateHttp" "traefikPrivateHttps" ];
          cond = "ct zone ${myUtils.listToNftablesSet (with marks.ct.zones; [
            lan vpnServices
          ])}";
        };
        ${upLink.ips.lan.address} = {
          protos.tcp = [ "traefikPublicHttp" "traefikPublicHttps" ];
          cond = "ct zone ${myUtils.listToNftablesSet (with marks.ct.zones; [
            cloudflare
          ])}";
        };
        ${upLink.ips.lanLocalDns.address} = {
          protos.tcp = [
            "traefikPrivateHttpLocalDns" "traefikPrivateHttpsLocalDns"
          ];
          cond = "ct zone ${myUtils.listToNftablesSet (with marks.ct.zones; [
            lan
          ])}";
        };
      } "accept"}
    '';
  };
}
