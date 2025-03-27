{ config, lib, myUtils, ... }:
let
  hostName = "paperless.hl.6e696e6f.dev";
  scheme = "https";
  dataDir = "/data/services/paperless";
  # Local patch while waiting for a solution upstream ([see](https://github.com/NixOS/nixpkgs/pull/388414))
  isLocalDB = config.services.paperless.database.createLocally or ((config.services.paperless.settings ? PAPERLESS_DBHOST == false) && (config.services.paperless ? environmentFile == true));
in
{
  nftablesService.services = {
    "paperless-web".chains = { "out" = ""; "in" = ""; }; # empty out/in to enable default fw
  };
  systemd.services = builtins.foldl' (acc: el:
    acc // {
      "${el}".serviceConfig = {
         TemporaryFileSystem = "/data";
         BindPaths = dataDir;
       };
    }
  ) {} [ "paperless-scheduler" "paperless-task-queue" "paperless-consumer" "paperless-web" "paperless-exporter" ];

  #systemd.services.paperless-scheduler.serviceConfig.PrivateNetwork = lib.mkForce isLocalDB;
  #systemd.services.paperless-consumer.serviceConfig.PrivateNetwork = lib.mkForce isLocalDB;
  
  bindings."${config.services.paperless.address}"."paperless" = config.services.paperless.port;
  services.paperless = {
    enable = true;
    address = "127.0.0.1";
    passwordFile = config.sops.secrets.paperlessAdminPassword.path;
    inherit dataDir;
    settings = {
      PAPERLESS_URL = "${scheme}://${hostName}";
    };
  };
}
