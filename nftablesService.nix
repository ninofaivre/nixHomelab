{ lib, config, ... }:
# TODO remove with at start of file to use it in equality
with lib;
let
  cfg = config.nftablesService;
  capitalizeFirstLetter = str:
    strings.toUpper (strings.substring 0 1 str) +
    strings.substring 1 (strings.stringLength str) str;
  convertUnitNameToSetName = unitName:
  let
    splited = lib.strings.splitString "-" unitName;
    setName =
      lib.strings.concatStrings
        ([ (builtins.head splited) ] ++
          (if cfg.namingConvention == "camel" then
             map capitalizeFirstLetter (builtins.tail splited)
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
            header = mkOption {
              type = types.str;
            };
            footer = mkOption {
              type = types.str;
            };
            preSubChain = mkOption {
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
        if cfg.namingConvention == "camel" then (capitalizeFirstLetter chainName) else "ERROR";
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
        in
        ''
          ${preSubChainString}chain ${chainName}${cfg.table.chainsSuffix} {
            ${chain.header}
            ${gotosString}
            ${chain.footer}
          }
        ''
      ) cfg.table.chains);
      gotoDstChains = builtins.concatStringsSep "\n" (mapAttrsToList (_: service:
        builtins.concatStringsSep "\n" (mapAttrsToList (chainName: chain:
          let
            inherit (cfg.table.chains.${chainName}) preSubChain;
            preSubChainsJmpString = if preSubChain == null then "" else
              "jump preSub${getSuffixChainName chainName}\n";
          in
          ''
            chain ${service.setName}${getSuffixChainName chainName} {
              ${preSubChainsJmpString}${chain}
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
