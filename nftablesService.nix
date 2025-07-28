{ lib, config, myUtils, ... }:
# TODO remove with at start of file to use it in equality
with lib;
let
  cfg = config.nftablesService;
  convertUnitNameToSetName = unitName:
  let
    splited = lib.strings.splitString "-" unitName;
    setName =
      lib.strings.concatStrings
        ([ (builtins.head splited) ] ++
          (if cfg.namingConvention == "camel" then
             map myUtils.capitalizeFirstLetter (builtins.tail splited)
           else if cfg.namingConvention == "snake" then
             map (el : "_${el}") (builtins.tail splited)
           else [ "err" ]
          )
        );
  in
    if (cfg.setNameHook == null) then setName else cfg.setNameHook el;
  getCgroupLevel = service: 
    let
      slice = config.systemd.services.${service}.serviceConfig.Slice or "system.slice";
    in 
      if slice == "system.slice" then
        2
      else
        1 + getCgroupLevel (removeSuffix ".slice" slice);
in
{
  options.nftablesService = 
  let
    serviceType = types.submodule ({name, ...}: {
      options = {
        setName = mkOption {
          default = (convertUnitNameToSetName name);
          type = types.str;
        };
        chains = mkOption {
          type = types.attrsOf types.str;
        };
      };
    });
  in
  {
    enable = mkEnableOption "nftablesService";
    namingConvention = mkOption {
      type = types.enum [ "snake" "camel" ];
      default = "camel";
    };
    services = mkOption {
      default = {};
      type = types.attrsOf serviceType;
      example = "[ paperless-web, traefik ]";
      description = ''
        A list of systemd services to make available in nftables through set of type cgroupsv2
        with NFSet and restartTriggers.
      '';
    };
    trackDomains = mkOption {
      type = types.listOf types.str;
      default = [];
    };
    getTargets = {
      nftables = mkOption {
        default = domains: suffix:
          lib.concatMapStringsSep "\n" (domain:
            cfg.trackedDomains.${domain}.targets.nftables.get suffix
          ) domains
        ;
        readOnly = true;
      };
    };
    trackedDomains = let
      # TODO quick hack with cool easter egg, handle error if domain
      # is using 42
      # currently only accepting *.myDomain.com and not *Domain.com because
      # of policy.suffix limitations.
      domain2setName = domain: myUtils.replacePrefix "*." "_42_." domain;
      getNftablesTarget = name: suffix: ''
        ip daddr @${domain2setName name}.v4 ${suffix}
        ip6 daddr @${domain2setName name}.v6 ${suffix}
      '';
      getDnsMasqTarget = name: [
        "/${name}/4#inet#${cfg.table.name}#${domain2setName name}.v4"
        "/${name}/6#inet#${cfg.table.name}#${domain2setName name}.v6"
      ];
      getAcnsTarget = name: [
        "${domain2setName name}.v4"
        "${domain2setName name}.v6"
      ];
      # cannot use toLua here because of vars as keys
      getKresAcnsPluginTarget = name: "policy." +
        (if lib.hasPrefix "*" name then "suffix" else "domains") + ''
          ({
              family = 1,
              tableName = "${cfg.table.name}",
              [kres.type.A] = {
                enabled = true,
                setName = "${domain2setName name}.v4",
              },
              [kres.type.AAAA] = {
                enabled = true,
                setName = "${domain2setName name}.v6",
              },
            },
            policy.todnames({'${lib.removePrefix "*." name}'})
          ),
        '';
    in mkOption {
      type = types.attrsOf (types.submodule ({name, ...}: {
        options = {
          targets = {
            nftables.get = mkOption {
              default = getNftablesTarget name;
              readOnly = true;
            };
            dnsmasq.get = mkOption {
              default = getDnsMasqTarget;
              readOnly = true;
            };
            kresAcnsPlugin.get = mkOption {
              default = getKresAcnsPluginTarget;
              readOnly = true;
            };
            acns.get = mkOption {
              default = getAcnsTarget;
            };
          };
          nftablesSets = mkOption {
            default = ''
              set ${domain2setName name}.v4 {
                type ipv4_addr
                timeout 4h
              }

              set ${domain2setName name}.v6 {
                type ipv6_addr
                timeout 4h
              }
            '';
            readOnly = true;
          };
        };
      }));
    };
    # getTrackedDomains = mkOption {
    #   default = domains: prefix: suffix:
    #     builtins.map(domain: cfg.trackedDomains.${domain}.target.n) domains
    #   ;
    #   readOnly = true;
    # };
    table = {
      family = mkOption {
        default = null;     
        # maybe it is possible to directly import this type from networking.nftables.tables
        type = types.enum [ "ip" "ip6" "inet" "arp" "bridge" "netdev" ];
        example = "inet";
      };
      name = mkOption {
        default = null;
        type = types.str;
        example = "filter";
      };
      chainsSuffix = mkOption {
        type = types.str;
        default = if cfg.namingConvention == "camel" then "Services" else "_services";
      };
      chains = mkOption {
        default = {};
        type = types.attrsOf (types.submodule {
          options = {
            content = mkOption {
              type = types.str;
            };
            preSubChain = mkOption {
              default = null;
              type = types.nullOr types.str;
            };
            postSubChain = mkOption {
              default = null;
              type = types.nullOr types.str;
            };
            preSubChainDuplicated = mkOption {
              default = null;
              type = types.nullOr types.str;
            };
            postSubChainDuplicated = mkOption {
              default = null;
              type = types.nullOr types.str;
            };
          };
        });
      };
    };
    setNameHook = mkOption {
      default = null;
      type = types.nullOr (types.functionTo types.str);
      example = "{ systemdUnitName, prefix ? \"\" }: \"${prefix}${systemdUnitName}\"";
      description = ''
        function hook to transform name of systemdUnit for final name of the set inserted to
        nftables.Service.table;
      '';
    };
  };
  config = mkIf cfg.enable {
    nftablesService.trackedDomains = builtins.listToAttrs (
      builtins.map (domain: { name = domain; value = {}; }) cfg.trackDomains
    );
    systemd.services = builtins.mapAttrs (key: value: {
      after = [ "nftables.service" ];
      requires = [ "nftables.service" ];
      bindsTo = [ "nftables.service" ];
      restartTriggers = [ config.systemd.units."nftables.service".unit ];
      serviceConfig = {
        NFTSet = "cgroup:${cfg.table.family}:${cfg.table.name}:${value.setName}";
      };
    }) cfg.services;

    networking.nftables.tables."${cfg.table.name}" =
    let
      setsString = builtins.concatStringsSep "\n" (mapAttrsToList (_: service:
        ''
          set ${service.setName} {
            type cgroupsv2;
          }
        ''
      ) cfg.services);
      getSuffixChainName = chainName:
        if cfg.namingConvention == "snake" then "_${chainName}" else
        if cfg.namingConvention == "camel" then (myUtils.capitalizeFirstLetter chainName) else "ERROR";
      gotoSrcChains = builtins.concatStringsSep "\n" (mapAttrsToList (chainName: chain:
        let
          gotosString = builtins.concatStringsSep "\n" (mapAttrsToList (serviceName: service:
            if (service.chains ? "${chainName}" == false) then
              ""
            else
              "socket cgroupv2 level ${toString (getCgroupLevel serviceName)} @${service.setName} goto ${service.setName}${getSuffixChainName chainName}"
          ) cfg.services);
          inherit (cfg.table.chains.${chainName}) preSubChain;
          preSubChainString = if preSubChain == null then "" else
            ''
              chain preSub${getSuffixChainName chainName} {
                ${preSubChain}
              }
            '';
          inherit (cfg.table.chains.${chainName}) postSubChain;
          postSubChainString = if postSubChain == null then "" else
           ''
             chain postSub${getSuffixChainName chainName} {
               ${postSubChain}
             }
           '';
        in
        ''
          ${preSubChainString}${postSubChainString}chain ${chainName}${cfg.table.chainsSuffix} {
            ${builtins.replaceStrings ["__generated__"] [gotosString] chain.content}
          }
        ''
      ) cfg.table.chains);
      gotoDstChains = builtins.concatStringsSep "\n" (mapAttrsToList (_: service:
        builtins.concatStringsSep "\n" (mapAttrsToList (chainName: chain:
          let
            inherit (cfg.table.chains.${chainName}) preSubChain preSubChainDuplicated;
            preSubChainsJmpString = if preSubChain == null then "" else
              "jump preSub${getSuffixChainName chainName}\n";
            inherit (cfg.table.chains.${chainName}) postSubChain postSubChainDuplicated;
            postSubChainJmpString = if postSubChain == null then "" else
              "\njump postSub${getSuffixChainName chainName}";
            varExpansion = str: builtins.replaceStrings ["__serviceName__"] [service.setName] str;
            preSubChainDuplicatedExpanded = if preSubChainDuplicated == null then "" else
              "${varExpansion preSubChainDuplicated}\n";
            postSubChainDuplicatedExpanded = if postSubChainDuplicated == null then "" else
              "\n${varExpansion postSubChainDuplicated}";
          in
          ''
            chain ${service.setName}${getSuffixChainName chainName} {
              ${preSubChainDuplicatedExpanded}${preSubChainsJmpString}${chain}${postSubChainJmpString}${postSubChainDuplicatedExpanded}
            }
          ''
        ) service.chains)
      ) cfg.services);
      balise = "### generated by nftablesService ###";
    in
    {
      inherit (cfg.table) family;
      content = "\n\n${balise}\n\n" + setsString + gotoSrcChains + gotoDstChains + "\n${balise}\n\n";
    };
  };
}
