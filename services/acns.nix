{ accessGroups }:
{ config, lib, ... }:
{
  services.acns = {
    enable = true;
    unixSocketAccessGroupName = accessGroups.acns.kresd;
    settings = {
      accessControl = {
        inet = {
          filter = (lib.flatten (lib.attrsets.mapAttrsToList (name: value:
            value.targets.acns.get name
          ) config.nftablesService.trackedDomains));
        };
      };
    };
  };
}
