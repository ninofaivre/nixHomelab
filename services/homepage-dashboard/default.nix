{ servicesConfig }:
{ config, myUtils, lib, ... }:
{
  nixBind.bindings."127.0.0.1".tcp.homepage = config.services.homepage-dashboard.listenPort;
  nftablesService.trackedDomains = config.nftablesService.trackDomains {
    https = ["api.github.com"];
  };
  nftablesService.services."homepage-dashboard".chains = {
    out = ''
      #${config.nftablesService.trackedDomains.https."api.github.com".target.nftables "ct state new accept"}
    '';
    "in" = "";
  };
  services.homepage-dashboard = {
    enable = true;
    settings = {
      title = "homelab homepage";
    };
    services = myUtils.dictToYamlNamedArray (
      builtins.mapAttrs (_: v: myUtils.dictToYamlNamedArray v) (
        builtins.foldl' (acc: {name,value}:
          acc // (let
            dashboard = {
              displayName = name;
              category = "uncategorized";
              description = "WIP description";
              href = "https://${value.domain}";
              icon = name;
            } // (value.dashboard or {});
          in {
            "${dashboard.category}" = (acc.${dashboard.category} or {}) // {
              "${dashboard.displayName}" = {
                inherit (dashboard) category description href icon;
              };
            };
          })
        ) {} (builtins.filter (el: el.value.dashboard != null) (lib.attrsToList servicesConfig))
      )
    );
    widgets = myUtils.namedElementsToYamlNamedArray { key = "widgetType"; array = [
      {
        widgetType = "resources";
        cpu = true;
        disk = "/";
        memory = true;
      }
      {
        widgetType = "greeting";
        text_size = "md";
        text = "You are connected from \${connexion.network} network via \${connexion.dns} DNS !";
      }
    ]; };
    customJS = ''
      async function populateCustomClientWidgetsData(customClientWidgets) {
        fetch("https://${servicesConfig.test.domain}/api").then(data => data.json()).then(data => {
          customClientWidgets.connexion = data
        }).catch(e => { console.error("failed to fetch https://${servicesConfig.test.domain}/api") })
      }
    '' + (builtins.readFile ./customJS.js);
  };
}
