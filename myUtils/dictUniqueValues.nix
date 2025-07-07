{ path, type ? null }:
{ lib, config, ... }:
with lib;
let
  quoteDotedStr = str: if (builtins.match (".*\\..*") str) != null then "\"${str}\"" else str;
  generatedAssertions = (builtins.foldl' (acc: { key, value }:
    let
      alreadyUsedValue = acc.set ? ${toString value};
    in
    {
      assertions = acc.assertions ++ (
        if alreadyUsedValue then
          [{
            assertion = false;
            message = "${key} : value ${toString value} already used by ${builtins.concatStringsSep "." (map quoteDotedStr path)}.${quoteDotedStr acc.set.${toString value}}";
          }]
        else []
      );
      set = acc.set  // (if alreadyUsedValue then {} else { "${toString value}" = key; });
    }
  ) { assertions = []; set = {}; } (mapAttrsToList (k: v: {key = k; value = v;}) (getAttrFromPath path config))).assertions;
in
{
  options = (if type == null then {} else (setAttrByPath path (mkOption {
    type = (types.attrsOf type);
  })));
  config = {
    assertions = generatedAssertions;
  };
}
