{ config, lib, upLink, myUtils, lanIp, lanLocalDnsIp, ... }:
{
  imports = [
    (myUtils.uniqueIntStore [ "networking" "nftables" "marks" "ct" "zones" ])
    (myUtils.uniqueIntStore [ "networking" "nftables" "marks" "marks" ])
    (myUtils.uniqueIntStore [ "networking" "nftables" "marks" "ct" "marks" ])
  ];

  networking.firewall = {
    extraInputRules = with config.bindings."${lanIp}"; with config.bindings."${lanLocalDnsIp}"; with config.networking.nftables.marks; ''
      iifname "${upLink}" ip daddr ${lanIp} tcp dport { ${toString traefikPublicHttp}, ${toString traefikPublicHttps}, ${toString ssh}, 53 } accept
      iifname "${upLink}" ip daddr ${lanIp} udp dport { 53, ${toString wireguardWg0} } accept

      iifname "${upLink}" ip daddr ${lanLocalDnsIp} tcp dport { ${toString traefikPrivateHttpLocalDns}, ${toString traefikPrivateHttpsLocalDns} } ct zone ${toString ct.zones.local} accept
      ct zone ${toString ct.zones.vpnServices} ip daddr ${lanIp} tcp dport { ${toString traefikPublicHttp}, ${toString traefikPublicHttps} } accept
      iifname { "${upLink}", "wg0" } ip daddr 127.0.0.1 ct status dnat accept comment "need to accept dnat to localhost because it isn't considered forwarding"
    '';
    filterForward = true; # default to accept established,related and dnat
    extraForwardRules = ''
    '';
  };

  networking.nftables = {
    enable = true;
    # could be better, currently if the @mycgroupv2 is misspelled, the check will not fail
    preCheckRuleset = "sed 's/socket cgroupv2 level . @[^;]\\+//g' -i ruleset.conf";
    marks = {
      marks = {
      };
      ct = {
        zones = {
          "local" = 1;
          "vpnServices" = 2;
        };
        marks = {
          "nftablesService" = 1;
        };
      };
    };
    tables = {
      "manualNat" = {
        family = "inet";
        content = with config.networking.nftables.marks; ''
          chain pre {
            type nat hook prerouting priority dstnat; policy accept;
            ip daddr ${lanIp} ct zone { ${toString ct.zones.local}, ${toString ct.zones.vpnServices} } dnat ip to tcp dport map { 80 : 127.0.0.1 . 81, 443 : 127.0.0.1 . 444 };
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
        content = with config.networking.nftables.marks; ''
          chain preZone {
            type filter hook prerouting priority raw; policy accept;
            iifname "${upLink}" ip saddr { 192.168.0.0/16 } ip saddr != { 192.168.1.254/32 } ct zone set ${toString ct.zones.local}
            iifname "wg0" ip saddr { 10.0.1.0/24 } ct zone set ${toString ct.zones.vpnServices}
          }
          
          chain outZone {
            type filter hook output priority raw; policy accept;
            oifname "${upLink}" ip daddr { 192.168.0.0/16 } ip daddr != { 192.168.1.254/32 } ct zone set ${toString ct.zones.local}
            oifname "wg0" ip daddr { 10.0.1.0/24 } ct zone set ${toString ct.zones.vpnServices}
          }

          chain out {
            type filter hook output priority filter; policy drop;
            oifname "wg0" ct state established,related accept
            oifname "eno1" ip6 saddr ::/0 accept
            oifname "eno1" ip saddr ${lanLocalDnsIp} ct state established,related accept
            oifname "eno1" ip saddr ${lanIp} accept
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
          header = ''
            type filter hook output priority filter; policy drop;
          '';
          footer = "accept;";
          preSubChain = ''
            ct mark set ${toString config.networking.nftables.marks.ct.marks.nftablesService}
            ct state established,related accept
          '';
        };
        "in" = {
          header = ''
            type filter hook input priority filter; policy drop;
          '';
          footer = "accept;";
          preSubChain = ''
            ct mark ${toString config.networking.nftables.marks.ct.marks.nftablesService} accept
          '';
        };
      };
    };
  };
}
