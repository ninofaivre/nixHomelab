{ servicesConfig }:
{ lib, myUtils, ... }:
let
  nftablesVectorLogFifoPath = "/run/ulogd/vector.pipe";
  vectorDnstapSocketPath = "/run/vector/dnstap.sock";
  accessGroups = builtins.mapAttrs (name: value:
      builtins.listToAttrs (map (item: {
        name = item;
        value = "${name}Access${myUtils.capitalizeFirstLetter item}";
      }) value)
    ) {
      vector = ["kresd"];
      acns = ["kresd"];
      ulogd = ["vector"];
    };
in
{
  users.groups =  builtins.listToAttrs (
    builtins.map (el: {
      name = el;
      value = {};
    }) (builtins.concatMap (el: builtins.attrValues el)
        (builtins.attrValues accessGroups))
  );
  imports = [
    (import ./knot-resolver {
      inherit accessGroups;
      inherit servicesConfig vectorDnstapSocketPath;
    })
    (import ./traefik {
      inherit servicesConfig;
      staging = false;
    })
    (import ./paperless {
      inherit (servicesConfig.paperless) domain dataDir;
      inherit (servicesConfig) kanidm;
    })
    (import ./caddy.nix { inherit (servicesConfig) test; })
    (import ./homepage-dashboard { inherit servicesConfig; })
    (import ./podman { inherit servicesConfig; })
    (import ./kanidm.nix {
      inherit (servicesConfig.kanidm) domain dataDir;
      inherit (servicesConfig) root;
    })
    (import ./acme.nix {
      inherit (servicesConfig.acme) dataDir;
      inherit (servicesConfig) kanidm;
    })
    (import ./vector.nix {
      inherit accessGroups;
      nftablesLogFifoPath = nftablesVectorLogFifoPath;
      dnstapSocketPath = vectorDnstapSocketPath;
    })
    (import ./ulogd.nix {
      inherit accessGroups;
      vectorLogFifoPath = nftablesVectorLogFifoPath;
    })
    (import ./acns.nix { inherit accessGroups; })
  ];
}
