{ config, lib,myUtils, networking, ... }:
{
  imports = [
    (myUtils.dictUniqueValues { path = [ "networking" "nftables" "marks" "ct" "zones" ]; type = lib.types.int; })
    (myUtils.dictUniqueValues { path = [ "networking" "nftables" "marks" "marks" ]; type = lib.types.int; })
    (myUtils.dictUniqueValues { path = [ "networking" "nftables" "marks" "ct" "marks" ]; type = lib.types.int; })
  ];

  networking.firewall =
    with config.nixBind;
    with config.networking.nftables.marks;
    with networking.interfaces;
  {
    # NOTE
    # policy is to allow there every publicly reachable service,
    # zones conditions (who is authorized to reach this service) are
    # defined in per service firewall (nftablesService)
    extraInputRules = ''
      ${getNftTargets {
        ${upLink.ips.lan.address} = {
          protos = {
            tcp = [
              "traefikPublicHttp" "traefikPublicHttps"
              "ssh"
              "knot-resolver"
            ];
            udp = [
              "knot-resolver"
              "wireguardServer"
            ];
          };
        };
        ${upLink.ips.lanLocalDns.address} = {
          protos = {
            tcp = [
              "traefikPrivateHttpLocalDns" "traefikPrivateHttpsLocalDns"
            ];
          };
        };
        ${vpnServer.ips.adminServices.address} = {
          protos = {
            tcp = [
              "ssh"
            ];
          };
        };
        # Still specifying input interfaces name just in case a new one
        # is added later on and is network reachable.
      } "iifname { \"${upLink.name}\", \"${vpnServer.name}\" } accept"}
      iifname { "${upLink.name}", "${vpnServer.name}" } ip daddr 127.0.0.1 ct status dnat accept comment "need to accept dnat to localhost because it isn't considered forwarding"
    '';
    filterForward = true; # default to accept established,related and dnat
    extraForwardRules = ''
    '';
  };

  boot.kernel.sysctl."net.ipv4.conf.all.route_localnet" = "1";
  networking.nftables = {
    enable = true;
    # could be better, currently if the @mycgroupv2 is misspelled, the check will not fail
    preCheckRuleset = "sed 's/socket cgroupv2 level . @[^;]\\+//g' -i ruleset.conf";
    marks = {
      marks = {
      };
      ct = {
        zones = {
          "lan" = 1;
          "vpnServices" = 2;
          "vpnAdminServices" = 3;
          "cloudflare" = 4;
        };
        marks = {
          "nftablesService" = 1;
        };
      };
    };
    tables =
      with config.networking.nftables.marks;
      with networking.interfaces;
    {
      "manualNat" = {
        family = "inet";
        content = ''
          chain pre {
            type nat hook prerouting priority dstnat; policy accept;
            ct zone { ${toString ct.zones.lan}, ${toString ct.zones.vpnServices} } ip daddr ${upLink.ips.lan.address} dnat ip to tcp dport map { ${toString config.nixBind.bindings."${networking.interfaces.upLink.ips.lan.address}".tcp.traefikPublicHttp} : 127.0.0.1 . ${toString config.nixBind.bindings."127.0.0.1".tcp.traefikPrivateHttp}, ${toString config.nixBind.bindings."${networking.interfaces.upLink.ips.lan.address}".tcp.traefikPublicHttps} : 127.0.0.1 . ${toString config.nixBind.bindings."127.0.0.1".tcp.traefikPrivateHttps} } 
          }
          chain post {
            type nat hook postrouting priority srcnat; policy accept;
          }
          chain out {
            type nat hook output priority mangle; policy accept;
          }
        '';
      };
      "filter" = {
        family = "inet";
        content = 
        let
          zones = builtins.foldl' (acc: el:
            {
              input = acc.input + "iifname ${el.ifname} ip saddr ${myUtils.listToNftablesSet el.includedIps} " + (if (el ? excludedIps == false) then "" else "ip saddr != ${myUtils.listToNftablesSet el.excludedIps} ") + "ct zone set ${toString el.zone}\n";
              output = acc.output + "oifname ${el.ifname} ip daddr ${myUtils.listToNftablesSet el.includedIps} " + (if (el ? excludedIps == false) then "" else "ip daddr != ${myUtils.listToNftablesSet el.excludedIps} ") + "ct zone set ${toString el.zone}\n";
            }
          ) { input = ""; output = ""; } [
            {
              ifname = upLink.name;
              includedIps = [upLink.ips.lan.cidrAddress];
              excludedIps = ["192.168.1.254/32"];
              zone = ct.zones.lan;
            }
            {
              ifname = upLink.name;
              # TODO
              # * mb handle ipv6 ?
              # * directly process https://www.cloudflare.com/ips-v4/#
              includedIps = [
                "103.21.244.0/22"
                "103.22.200.0/22"
                "103.31.4.0/22"
                "104.16.0.0/13"
                "104.24.0.0/14"
                "108.162.192.0/18"
                "131.0.72.0/22"
                "141.101.64.0/18"
                "162.158.0.0/15"
                "172.64.0.0/13"
                "173.245.48.0/20"
                "188.114.96.0/20"
                "190.93.240.0/20"
                "197.234.240.0/22"
                "198.41.128.0/17"
              ];
              zone = ct.zones.cloudflare;
            }
            {
              ifname = vpnServer.name;
              includedIps = [vpnServer.ips.privateServices.cidrAddress];
              zone = ct.zones.vpnServices;
            }
            {
              ifname = vpnServer.name;
              includedIps = [vpnServer.ips.adminServices.cidrAddress];
              zone = ct.zones.vpnAdminServices;
            }
          ];
        in
        ''
          ${lib.strings.concatMapStrings ({ nftablesSets, ... }: nftablesSets) (builtins.attrValues config.nftablesService.trackedDomains)}

          chain preZone {
            type filter hook prerouting priority raw; policy accept;
            ${zones.input}
          }

          chain outZone {
            type filter hook output priority raw; policy accept;
            ${zones.output}
          }

          chain out {
            type filter hook output priority filter; policy drop;
            oifname "${vpnServer.name}" ct state established,related accept
            oifname "${upLink.name}" ip saddr ${upLink.ips.lanLocalDns.address} ct state established,related accept
            oifname "${upLink.name}" ip6 saddr ::/0 accept
            oifname "${upLink.name}" ip saddr ${upLink.ips.lan.address} accept
            ip saddr 127.0.0.1 ct status dnat accept
            oifname "lo" accept
          }
        '';
      };
    };
  };

  nftablesService = {
    enable = true;
    namingConvention = "camel";
    table = {
      family = "inet";
      name = "filter";
      chains = {
        "out" = {
          content = ''
            type filter hook output priority filter; policy drop;
            __generated__
            accept;
          '';
          preSubChain = ''
            ct mark set ${toString config.networking.nftables.marks.ct.marks.nftablesService}
            ct state established,related accept
          '';
          postSubChainDuplicated = ''
            log prefix "nftablesServices,nftablesService.src=__serviceName__" group ${toString config.services.ulogd.settings.logVector.group}
          '';
        };
        "in" = {
          content = ''
            type filter hook input priority filter; policy drop;
            __generated__
            accept;
          '';
          preSubChain = ''
            ct mark ${toString config.networking.nftables.marks.ct.marks.nftablesService} accept
          '';
          postSubChainDuplicated = ''
            log prefix "nftablesServices,nftablesService.dst=__serviceName__" group ${toString config.services.ulogd.settings.logVector.group}
          '';
        };
      };
    };
  };
}
