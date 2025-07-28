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
  replacePrefix = oldPrefix: newPrefix: oldString:
  let
    newString = lib.strings.removePrefix oldPrefix oldString;
  in
    if (lib.strings.stringLength newString) != (lib.strings.stringLength oldString) then
      "${newPrefix}${newString}"
    else
      newString
  ;
  replaceSuffix = oldSuffix: newSuffix: oldString:
  let
    newString = lib.strings.removeSuffix oldSuffix oldString;
  in
    if (lib.strings.stringLength newString) != (lib.strings.stringLength oldString) then
      "${newString}${newSuffix}"
    else
      newString
  ;
  capitalizeFirstLetter = str:
    lib.strings.toUpper (lib.strings.substring 0 1 str) +
    lib.strings.substring 1 (lib.strings.stringLength str) str
  ;
  namedElementsToYamlNamedArray = { key, array }:
    map (el: { "${el.${key}}" = el; }) array
  ;
  dictToYamlNamedArray = dict: map ({ name, value }:
      { "${name}" = value; })
    (lib.attrsets.attrsToList dict)
  ;
  listToNftablesSet = ports:
    (builtins.foldl' (acc: el:
      acc + "${toString el}, "
    ) "{ " (lib.sublist 0 ((lib.length ports) - 1) ports))
    + "${toString (builtins.elemAt ports ((lib.length ports) - 1))} }"
  ;
}
