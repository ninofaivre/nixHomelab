{ servicesConfig }:
{ pkgs, lib, ... }:
{
  imports = [
    (import ./wgportal.nix {
      inherit (servicesConfig.wgportal) domain dataDir;
      inherit (servicesConfig.wgportal.dashboard) displayName;
    })
  ];

  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = true;
    defaultNetwork.settings = {
      # Required for container networking to be able to use names.
      dns_enabled = true;
    };
  };

  # Enable container name DNS for non-default Podman networks.
  # https://github.com/NixOS/nixpkgs/issues/226365
  networking.firewall.interfaces."podman*".allowedUDPPorts = [ 53 ];

  virtualisation.oci-containers.backend = "podman";
}
