{ vectorDnstapSocketPath, accessGroups }:
{ pkgs, lib, myPkgs, ... }: {
  systemd.services."kresd@" = {
    wants = [ "vectorDnstapSocketWatcher@%i.service" ];
  };
  systemd.services."vectorDnstapSocketWatcher@" = {
    after = [ "kresd@%i.service" ];
    environment = {
      SYSTEMD_INSTANCE = "%i";
    };
    serviceConfig = {
      ExecStart = lib.getExe (pkgs.writeShellApplication {
        name = "vectorDnsTapSocketWatcher";
        runtimeInputs = with pkgs; [
          inotify-tools
          socat
          myPkgs.yafw
        ];
        text = let
          kresdControlSocketDir = "/run/knot-resolver/control";
        in ''
          kresdControlSocketPath="${kresdControlSocketDir}/''${SYSTEMD_INSTANCE}"

          function configureKresdDnstap {
            chgrp ${accessGroups.vector.kresd} ${vectorDnstapSocketPath} &
            echo "asking kresd instance ''${SYSTEMD_INSTANCE} to reconnect to vector dnstap unix socket"
            socat - <<< "dnstap.foreignLoad()" "UNIX-CONNECT:''${kresdControlSocketPath}" >/dev/null
          }

          yafw -m all \
            "$kresdControlSocketPath" \
            "${vectorDnstapSocketPath}" | while read -r; do
              configureKresdDnstap || :
            done
        '';
      });
    };
  };
}
