{ lib, config, myUtils, ... }:
let
  cfg = config.nixBind;
in
{
  options.nixBind = with lib; {
    bindings = mkOption {
      default = {};
      type = types.attrsOf (types.submodule ({name, ...}: {
        options = {
          tcp = mkOption {
            default = {};
            type = types.attrsOf types.int;
          };
          udp = mkOption {
            default = {};
            type = types.attrsOf types.int;
          };
        };
      }));
      apply = values:
        builtins.mapAttrs (name: value:
          if name == "0.0.0.0" then value else {
            tcp = values."0.0.0.0".tcp // value.tcp;
            udp = values."0.0.0.0".udp // value.udp;
          }
        ) values;
    };
    getNftTarget = mkOption {
      default = { address, protocol, ports }:
      "ip daddr ${address} ${protocol} dport ${myUtils.listToNftablesSet
        (map (port: (toString cfg.bindings."${address}"."${protocol}"."${port}")) ports)}";
      readOnly = true;
    };
    getAddressWithPort = mkOption {
      default = address: protocol: port:
      "${address}:${toString cfg.bindings."${address}"."${protocol}"."${port}"}";
      readOnly = true;
    };
  };
}
