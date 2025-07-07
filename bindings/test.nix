{ lib, config, myUtils, ... }:
{
  config.assertions = builtins.concatLists ((map (el:
    (myUtils.dictUniqueValues {
      path = [ "nixBind" "bindings" el "udp" ];
    } { inherit lib config; }).config.assertions) (builtins.attrNames config.nixBind.bindings)) ++
    (map (el:
    (myUtils.dictUniqueValues {
      path = [ "nixBind" "bindings" el "tcp" ];
    } { inherit lib config; }).config.assertions) (builtins.attrNames config.nixBind.bindings)));
}
