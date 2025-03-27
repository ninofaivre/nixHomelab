{
  description = "experiment flake config";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, sops-nix }:
  let
    myUtils = (import ./myUtils/myUtils.nix) { inherit (nixpkgs) lib; };
    minimalProfile = (import "${nixpkgs.outPath}/nixos/modules/profiles/minimal.nix");
    upLink = "eno1";
    lanIp = "192.168.1.99";
    lanLocalDnsIp = "192.168.1.100";
  in
  {
    nixosConfigurations."NixOsNas" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit myUtils;
        inherit minimalProfile;
        inherit upLink;
        inherit lanIp;
        inherit lanLocalDnsIp;
      };
      modules = [
        minimalProfile
        sops-nix.nixosModules.sops
        ./configuration.nix
        ./sops-nix.nix
        ./networking/networking.nix
        ./nftablesService.nix
        ./services/services.nix
      ];
    };
  };
}
