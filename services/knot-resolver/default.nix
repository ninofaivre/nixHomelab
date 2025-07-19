{ servicesConfig, vectorDnstapSocketPath }:
{ config, lib, networking, myPkgs, ... }:
{
  imports = [
    (import ./vectorSocketDirtyFix.nix { inherit vectorDnstapSocketPath; })
  ];
  nixBind.bindings = {
    "${networking.interfaces.upLink.ips.lan.address}" = {
      udp."knot-resolver" = 53;
      tcp."knot-resolver" = 53;
    };
    "127.0.0.1" = {
      udp."knot-resolver" = 53;
      tcp."knot-resolver" = 53;
    };
  };

  users.groups."vectorAccessKresd" = {};
  systemd.services."kresd@".serviceConfig.SupplementaryGroups = [
    config.services.acns.unixSocketAccessGroupName
    "vectorAccessKresd"
  ];
  systemd.services."kresd@".serviceConfig.RuntimeDirectoryMode = lib.mkForce "0771";

  services.kresd =
  let
    domains = builtins.filter (domain: domain != null) (lib.attrsets.mapAttrsToList (_: value: value.domain) servicesConfig);
  in
  {
    enable = true;
    listenPlain = [ "127.0.0.1:53" "${networking.interfaces.upLink.ips.lan.address}:53" ];
    luaModules = [ myPkgs.kresdLuaModules.acns ];
    extraConfig = ''
      modules = {
        'hints > iterate',
        'policy',
        'nsid',
        'dnstap',
        'acns',
      }

      acns.config ({
        socketPath = "/run/acns/acns.sock",
        unixSocketAccessGroupName = "${config.services.acns.unixSocketAccessGroupName}",
        perfStats = false,
        rules = {
        --[[
          policy.domains({
              family = 1,
              tableName = "filter",
              setName = "api.github.com.v4"
            },
            policy.todnames({'api.github.com'})
          ),
        ]]
          policy.domains({
              family = 1,
              tableName = "filter",
              setName = "wronnnnnnng"
            },
            policy.todnames({'google.com'})
          )
        }
      })

      cache.size = 150 * MB
      internalDomains = ${lib.generators.toLua {} domains}
      -- cannot use internalDomains here because todnames do not create a new dict but change the one he gets as a parameter
      internalDomainsTod = policy.todnames(${lib.generators.toLua {} domains})
      forwarders = {
        { '1.1.1.1', hostname='one.one.one.one' },
        { '1.0.0.1', hostname='one.one.one.one' },
        { '8.8.8.8', hostname='dns.google' },
        { '8.8.4.4', hostname='dns.google' },
        { '9.9.9.9', hostname='dns.quad9.net' }
      }
      for _, domain in ipairs(internalDomains) do
        hints[domain] = '${networking.interfaces.upLink.ips.lanLocalDns.address}'
      end
      
      policy.add(policy.domains(policy.PASS, internalDomainsTod))
      policy.add(policy.all(policy.TLS_FORWARD(forwarders)))
      
      _G['dnstap'] = {
        config = dnstap.config,
        foreignLoad = function ()
          print('(re)Loading dnstap')
          return dnstap.config({
            socket_path = "${vectorDnstapSocketPath}",
            identity = nsid.name() or "",
            client = { log_queries = false, log_responses = true }
          })
        end
      }
    '';
  };
}
