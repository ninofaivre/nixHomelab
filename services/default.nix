{ servicesConfig }:
{ ... }:
let
  nftablesServiceLogFifo = "/var/run/ulogd/nftablesService.pipe";
  vectorDnstapSocketPath = "/run/vector/dnstap.sock";
in
{
  imports = [
    (import ./knot-resolver {
      inherit servicesConfig vectorDnstapSocketPath;
    })
    (import ./traefik.nix { inherit servicesConfig; })
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
      inherit nftablesServiceLogFifo;
      dnstapSocketPath = vectorDnstapSocketPath;
    })
    (import ./ulogd.nix { inherit nftablesServiceLogFifo; })
    ./acns.nix
  ];
}
