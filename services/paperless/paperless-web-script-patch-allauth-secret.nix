{ providers }:
{ lib, pkgs, ... }:
let
  credentialsInjectionRes = builtins.foldl' (acc: { name, value }:
    let
      providerType = name;
      providersRes = builtins.foldl' (acc: provider:
        if !(provider ? secretFile) || provider ? secret then
          acc // { index = acc.index + 1; }
        else let
          systemdCredentialName = "allauth_${providerType}_APPS_${toString acc.index}_secretFile";
        in {
          index = acc.index + 1;
          args = acc.args + ''--rawfile ${systemdCredentialName} ''${CREDENTIALS_DIRECTORY}/${systemdCredentialName}'';
          filter = let
            target = ".${providerType}.APPS[${toString acc.index}]";
          in
            acc.filter + "${target}.secret=\$${systemdCredentialName} | ";
          systemdCredentials = acc.systemdCredentials // {
            "${systemdCredentialName}" = provider.secretFile;
          };
        }
      ) { inherit (acc) systemdCredentials filter args; index = 0; } (if value ? APPS then value.APPS else []);
    in
    { inherit (providersRes) systemdCredentials filter args; }
  ) { args = ""; filter = ""; systemdCredentials = {}; } (lib.attrsets.attrsToList providers);
  jqInjection = "${credentialsInjectionRes.args} '${credentialsInjectionRes.filter} .'";
  inherit (credentialsInjectionRes) systemdCredentials;
in {
  systemd.services.paperless-web.script = lib.mkBefore ''
    export PAPERLESS_SOCIALACCOUNT_PROVIDERS="$(<<< "$PAPERLESS_SOCIALACCOUNT_PROVIDERS" ${lib.getExe pkgs.jq} ${jqInjection})"
  '';
  services.paperless.settings.PAPERLESS_SOCIALACCOUNT_PROVIDERS = builtins.toJSON (
    builtins.mapAttrs (providerType: value: value // { APPS = map (provider: builtins.removeAttrs provider ["secretFile"]) (value.APPS or []); }) providers
  );
  systemd.services.paperless-web.serviceConfig.LoadCredential = lib.attrsets.mapAttrsToList (systemdCredentialName: path: "${systemdCredentialName}:${path}") systemdCredentials;
}
