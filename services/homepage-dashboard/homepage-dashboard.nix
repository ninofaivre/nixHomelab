{ config, myUtils, ... }:
{
  services.homepage-dashboard = {
    enable = true;
    settings = {
      title = "homelab homepage";
    };
    services = myUtils.dictToYamlNamedArray {
      "documents" = myUtils.dictToYamlNamedArray {
        "paperless" = {
          description = "open-source document management system";
          href = "https://paperless.hl.6e696e6f.dev";
          icon = "paperless";
        };
      };
    };
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
        fetch("https://test.hl.6e696e6f.dev/api").then(data => data.json()).then(data => {
          customClientWidgets.connexion = data
        }).catch(e => { console.error("failed to fetch https://test.hl.6e696e6f.dev") })
      }
    '' + (builtins.readFile ./customJS.js);
  };
}
