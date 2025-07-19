{ vectorDnstapSocketPath }:
{ pkgs, lib, ... }: {
  systemd.services."kresd@" = {
    wants = [ "vectorDnstapSocketWatcher@%i.service" ];
  };
  systemd.services."vectorDnstapSocketWatcher@" = {
    partOf = [ "kresd@%i.service" ];
    after = [ "kresd@%i.service" ];
    environment = {
      SYSTEMD_INSTANCE = "%i";
    };
    serviceConfig = {
      ExecStart = lib.getExe (pkgs.writeShellApplication {
        name = "vectorDnsTapSocketWatcher";
        runtimeInputs = with pkgs; [inotify-tools socat procps];
        text = let
          kresdControlSocketDir = "/run/knot-resolver/control";
        in ''
          kresdControlSocketPath="${kresdControlSocketDir}/''${SYSTEMD_INSTANCE}"

          function configureKresdDnstap {
            chown :vectorAccessKresd ${vectorDnstapSocketPath} &
            socat - <<< "dnstap.foreignLoad()" "UNIX-CONNECT:''${kresdControlSocketPath}" >/dev/null &
          }

          # wait for kresd control socket to exists
          coproc kresdControlSocketWatcher {
            inotifywait -mr /run/knot-resolver -e create --format '%w%f' 2>&1
          }
          while read -r line <&"''${kresdControlSocketWatcher[0]}"; do
            if [ "$line" == "Watches established." ]; then break ; fi
          done
          if ! [ -S "$kresdControlSocketPath" ]; then
            while read -r file <&"''${kresdControlSocketWatcher[0]}"; do
              if [ "$file" == "$kresdControlSocketPath" ] && [ -S "$kresdControlSocketPath" ]; then
                break ;
              fi
            done
          fi
          # shellcheck disable=SC2154 # var created by coproc
          kill "$kresdControlSocketWatcher_PID"
          wait || :

          # every time vector dnstap socket is (re)created, (re)configure kresd dnstap
          while true; do
            echo "watching for creation of vector socket..."
            coproc vectorDnstapSocketWatcher {
              inotifywait -mr /run -e create --format '%w%f' 2>&1
            }
            while read -r line <&"''${vectorDnstapSocketWatcher[0]}"; do
              if [ "$line" == "Watches established." ]; then break ; fi
            done
            if ! [ -S "${vectorDnstapSocketPath}" ]; then
              while read -r file <&"''${vectorDnstapSocketWatcher[0]}"; do
                if [ "$file" == "${vectorDnstapSocketPath}" ] && [ -S "${vectorDnstapSocketPath}" ]; then
                  echo "vector socket has been created !"
                  break ;
                fi
              done
            else
              echo "vector socket already exists !"
            fi
            # shellcheck disable=SC2154 # var created by coproc
            kill "$vectorDnstapSocketWatcher_PID"
            configureKresdDnstap
            wait || :

            echo "watching for deletion of vector socket..."
            inotifywait -qq "${vectorDnstapSocketPath}" -e delete_self 2>/dev/null || :
            echo "vector socket deleted !"
          done
        '';
      });
    };
  };
}
