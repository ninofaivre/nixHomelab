{ config, networking, myUtils, ... }:
let
  inherit (networking) interfaces;
in
{
  nixBind.bindings = {
    "${interfaces.upLink.ips.lan.address}".tcp."ssh" = 22;
    "${interfaces.vpnServer.ips.adminServices.address}".tcp."ssh" = 22;
  };
  nftablesService.services."ssh".chains =
  let
    inherit (config) nixBind;
    inherit (config.networking.nftables) marks;
  in
  {
    "in" = ''
      ${nixBind.getNftTargets {
        ${interfaces.upLink.ips.lan.address} = {
          protos.tcp = [ "ssh" ];
          cond = "ct zone ${myUtils.listToNftablesSet (with marks.ct.zones; [
            lan
          ])}";
        };
        ${interfaces.vpnServer.ips.adminServices.address} = {
          protos.tcp = [ "ssh" ];
          cond = "ct zone ${myUtils.listToNftablesSet (with marks.ct.zones; [
            vpnAdminServices
          ])}";
        };
      } "accept"}
    '';
  };
  systemd.services.sshd.after = [
    "systemd-networkd-wait-online.service"
    "wireguard-wg0.service"
  ];
  services.openssh = {
    enable = true;
    openFirewall = false;
    listenAddresses =
    let
      inherit (config.nixBind) bindings;
    in
    [
      {
        addr = interfaces.upLink.ips.lan.address;
        port = bindings.${interfaces.upLink.ips.lan.address}.tcp.ssh;
      }
      {
        addr = interfaces.vpnServer.ips.adminServices.address;
        port = bindings.${interfaces.vpnServer.ips.adminServices.address}.tcp.ssh;
      }
    ];
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitUserEnvironment = "yes";
      AcceptEnv = "TERM";
    };
  };
}
