# TODO :
# * find out why not cached dns request are slow (slower than directly requesting forwarders)
{ servicesConfig, vectorDnstapSocketPath, accessGroups }:
{ config, lib, networking, myPkgs, ... }:
{
  imports = [
    (import ./vectorSocketDirtyFix.nix { inherit vectorDnstapSocketPath accessGroups; })
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

  systemd.services."kresd@".serviceConfig.SupplementaryGroups = [
    config.services.acns.unixSocketAccessGroupName
    accessGroups.vector.kresd
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

      log_level('info')
      acns.config ({
        socketPath = "/run/acns/acns.sock",
        unixSocketAccessGroupName = "${config.services.acns.unixSocketAccessGroupName}",
        perfStats = false,
        debug = true,
        rules = {${lib.strings.concatStringsSep
          "\n"
          (lib.attrsets.mapAttrsToList (name: value:
            (value.targets.kresAcnsPlugin.get name)
          ) config.nftablesService.trackedDomains)
        }}
      })

      cache.size = 150 * MB
      internalDomains = ${lib.generators.toLua {} domains}
      -- cannot use internalDomains here because todnames do not create a new dict but change the one it gets as a parameter
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
