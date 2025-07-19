{
  description = "experiment flake config";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

    nixpkgs-fork-systemd-credentials.url = "github:ninofaivre/nixpkgs/kanidm-provision-use-systemd-credentials";
    # nixpkgs-fork-kresd-add-lua-modules.url = "github:ninofaivre/nixpkgs/kresd-add-lua-modules";
    nixpkgs-fork-kresd-add-lua-modules.url = "path:/home/nino/nixpkgs-fork-kresd-add-lua-modules";

    sops-nix.url = "github:Mic92/sops-nix";

    #kresd-acns.url = "github:ninofaivre/kresd-acns";
    kresd-acns.url = "path:/home/nino/kresd-acns";
    #acns.url = "github:ninofaivre/acns";
    acns.url = "path:/home/nino/acns";
    yafw.url = "github:ninofaivre/yafw";
  };

  outputs = {
    self, nixpkgs, nixpkgs-unstable,
    nixpkgs-fork-systemd-credentials, nixpkgs-fork-kresd-add-lua-modules,
    sops-nix, kresd-acns, acns, yafw
  }:
  let
    system = "x86_64-linux";
    myUtils = (import ./myUtils/myUtils.nix) { inherit (nixpkgs) lib; };
    minimalProfile = (import "${nixpkgs.outPath}/nixos/modules/profiles/minimal.nix");
    unstablePkgs = import nixpkgs-unstable { inherit system; };
    #masterPkgs = import nixpkgs-master { inherit system; };
    myPkgs = kresd-acns.packages.${system} ++ yafw.packages.${system};
    networking = {
      interfaces = builtins.foldl' (acc: {name, value}:
        acc // {
          "${name}" = value // {
            ips = builtins.foldl' (acc: {name, value}:
              acc // {
                "${name}" = value // { cidrAddress = "${value.address}/${toString value.cidr}"; };
              }
            ) {} (nixpkgs.lib.attrsets.attrsToList value.ips);
          };
        }
      ) {} (nixpkgs.lib.attrsets.attrsToList {
        upLink = {
          name = "eno1";
          ips = {
            lan = {
              address = "192.168.1.99";
              cidr = 24;
            };
            lanLocalDns = {
              address = "192.168.1.100";
              cidr = 24;
            };
          };
        };
        vpnServer = {
          name = "wg0";
          ips = {
            privateServices = {
              address = "10.0.1.1";
              cidr = 24;
            };
            adminServices = {
              address = "10.0.2.1";
              cidr = 24;
            };
            netflix = {
              address = "10.0.3.1";
              cidr = 24;
            };
          };
        };
      });
    };
    homelabDomain = "hl.6e696e6f.dev";
    zfsPoolMnt = "/data";
    servicesConfig = builtins.mapAttrs (key: value:
      value // (
        if (value ? domain) then {}
        else { domain = "${key}.${homelabDomain}"; }
      ) // (
        if (value ? dataDir) then {}
        else { dataDir = "${zfsPoolMnt}/services/${key}"; }
      )
    ) {
      root = {
        dataDir = null;
        dashboard = null;
        domain = homelabDomain;
      };
      homepage-dashboard = {
        dataDir = null;
        dashboard = null;
        domain = "homepage.${homelabDomain}";
      };
      test = {
        dataDir = null;
        dashboard.icon = "mdi-test-tube-#349e06";
      };
      wgportal = {
        dashboard = {
          displayName = "WireGuard Portal";
          category = "authentication";
          icon = "wireguard";
        };
      };
      kanidm = {
        dashboard.category = "authentication";
      };
      acme = {
        dataDir = "${zfsPoolMnt}/acme";
        domain = null;
        dashboard = null;
      };
      paperless = {
        dashboard = {
          category = "document";
          description = "open-source document management system";
        };
      };
    };
  in
  {
    nixosConfigurations."NixOsNas" = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit myUtils minimalProfile networking unstablePkgs myPkgs;
      };
      modules = [
        minimalProfile
        ({...}: {
          disabledModules = [
            # TODO move to stable when paperless 15.1 (at least) is released
            "services/misc/paperless.nix"
            # TODO move from fork when PR gets merged
            "services/security/kanidm.nix"
            "services/networking/kresd.nix"
          ];
        })
        # TODO move to stable when paperless 15.1 (at least) will be on it
        "${nixpkgs-unstable}/nixos/modules/services/misc/paperless.nix"
        # TODO move from fork when PR gets merged
        "${nixpkgs-fork-systemd-credentials}/nixos/modules/services/security/kanidm.nix"
        "${nixpkgs-fork-kresd-add-lua-modules}/nixos/modules/services/networking/kresd.nix"
        sops-nix.nixosModules.sops
        acns.nixosModules.acns
        ./bindings/bindings.nix
        ./configuration.nix
        ./sops-nix.nix
        ./networking/networking.nix
        ./nftablesService.nix
        (import ./services { inherit servicesConfig; })
      ];
    };
  };
}
