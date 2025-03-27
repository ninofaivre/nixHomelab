{ lib }:
let
  assertions = import ./asserts/asserts.nix;
  uniqueIntStore = import ./uniqueIntStore.nix;
in
{
  inherit assertions;
  inherit uniqueIntStore;
  prefixEveryLine = { prefix, lines }:
    (lib.strings.concatStringsSep "\n" (lib.map (line: if (line == "") then "" else prefix + line) (lib.strings.splitString "\n" lines)));
  namedElementsToYamlNamedArray = { key, array }: map (el: { "${el.${key}}" = el; }) array;
  dictToYamlNamedArray = dict: map ({ name, value }:
      { "${name}" = value; })
    (lib.attrsets.attrsToList dict);
}
