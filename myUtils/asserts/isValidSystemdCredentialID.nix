let
  err = "is not a valid systemd credential ID :";
in
value:
  assert builtins.isString value;
  assert builtins.match "" value == null || throw "'${value}' ${err} must not be an empty string";
  assert builtins.stringLength value <= 255 || throw "'${value}' ${err} must be less than 255 chars";
  assert builtins.match "\\." value == null || throw "'${value}' ${err} must not be a single dot";
  assert builtins.match "\\.\\." value == null || throw "'${value}' ${err} must not be a double dot";
  assert builtins.match "[^/]*" value != null || throw "'${value}' ${err} must not contain any slash";
  assert builtins.match "[^:]*" value != null || throw "'${value}' ${err} must not contain any colon";
  assert builtins.match "[ -~]*" value != null || throw "'${value}' ${err} every char must be in ascii range [32,127)";
  value
