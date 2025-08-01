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
          # TODO make proto a submodule to allow any proto
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
    getNftTargets = mkOption {
      default = bindings: action:
      let
        getNftPorts = address: proto: ports:
          myUtils.listToNftablesSet (map (port:
            toString cfg.bindings."${address}"."${proto}"."${port}"
          ) ports)
        ;
      in
        lib.concatMapAttrsStringSep "" (address: value:
          lib.concatMapAttrsStringSep
            ""
            (proto: ports:
              "ip daddr ${address} ${proto} dport ${getNftPorts address proto ports} ${
                if builtins.hasAttr "cond" value then
                  " ${value.cond}"
                else
                  ""
              } ${action}\n"
            ) value.protos
        ) bindings
      ;
      readOnly = true;
    };
    getAddressWithPort = mkOption {
      default = address: proto: port:
      "${address}:${toString cfg.bindings."${address}"."${proto}"."${port}"}";
      readOnly = true;
    };
  };
}
