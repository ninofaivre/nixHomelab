{ lib }:
let
  assertions = import ./asserts/asserts.nix;
  dictUniqueValues = import ./dictUniqueValues.nix;
in
{
  inherit assertions;
  inherit dictUniqueValues;
  prefixEveryLine = { prefix, lines }:
    (lib.strings.concatStringsSep "\n" (lib.map (line: if (line == "") then "" else prefix + line) (lib.strings.splitString "\n" lines)));
  namedElementsToYamlNamedArray = { key, array }: map (el: { "${el.${key}}" = el; }) array;
  dictToYamlNamedArray = dict: map ({ name, value }:
      { "${name}" = value; })
    (lib.attrsets.attrsToList dict);
  listToNftablesSet = ports:
    (builtins.foldl' (acc: el:
      acc + "${toString el}, "
    ) "{ " (lib.sublist 0 ((lib.length ports) - 1) ports))
    + "${builtins.elemAt ports ((lib.length ports) - 1)} }";
}
