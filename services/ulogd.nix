{ nftablesServiceLogFifo }:
{ pkgs, ... }:
let
  fifoScript = pkgs.writeShellScript "pre-start" ''
    if [ ! -p ${nftablesServiceLogFifo} ]; then
      rm -f ${nftablesServiceLogFifo}
      mkfifo -m 644 ${nftablesServiceLogFifo}
    fi
  '';
in
{
  systemd.services.ulogd = {
    serviceConfig = {
      RuntimeDirectory = "ulogd";
      ExecStartPre = fifoScript;
    };
  };
  services.ulogd.enable = true;
  services.ulogd.settings = {
    global = {
      stack = [
        "logNftablesService:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str:IP2STR,emuNftablesService:GPRINT"
      ];
    };
    emuNftablesService = {
      file = nftablesServiceLogFifo;
      sync = 1;
    };
    logNftablesService.group = 2;
  };
}
