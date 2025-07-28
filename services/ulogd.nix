{ vectorLogFifoPath, accessGroups }:
{ pkgs, ... }:
{
  systemd.services.ulogd.serviceConfig = {
    RuntimeDirectory = "ulogd";
    RuntimeDirectorMode = "771";
    ExecStartPre = pkgs.writeShellScript "createVectorFifo" ''
      rm -f "${vectorLogFifoPath}"
      tmpFifoPath="$(mktemp -u /run/vector-fifo.XXXXXX)"
      mkfifo -m 240 "$tmpFifoPath"
      chgrp ${accessGroups.ulogd.vector} "$tmpFifoPath"
      mv "$tmpFifoPath" "${vectorLogFifoPath}"
    '';
    SupplementaryGroups = [
      accessGroups.ulogd.vector
    ];
  };
  services.ulogd.enable = true;
  services.ulogd.settings = {
    global = {
      stack = [
        "logVector:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str:IP2STR,emuVectorFifo:GPRINT"
      ];
    };
    emuVectorFifo = {
      file = vectorLogFifoPath;
      sync = 1;
    };
    logVector.group = 2;
  };
}
