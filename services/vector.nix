# TODO:
# ulogd -> vector -> loki -> grafana
{ nftablesLogFifoPath, dnstapSocketPath, accessGroups }:
{ config, pkgs, lib, unstablePkgs, myPkgs, ... }:
let
  readFifoScript = lib.getExe (pkgs.writeShellApplication {
    name = "readFifo";
    runtimeInputs = [ myPkgs.yafw ];
    text = ''
      fifoPath="$1"
      yafw "$fifoPath" | while read -r; do
        cat "$fifoPath" || :
      done
    '';
  });
in
{
  systemd.services.vector.serviceConfig = {
    ReadOnlyPaths = [ nftablesLogFifoPath ];
    ExecPaths = [ readFifoScript ];
    RuntimeDirectory = "vector";
    RuntimeDirectoryMode = "771";
    SupplementaryGroups = [
      accessGroups.ulogd.vector
      # accessGroups.vector.kresd will be usefull when being able
      # to define unix group owner for unix dnstap socket
    ];
  };

  services.vector.enable = true;
  services.vector.package = unstablePkgs.vector;
  services.vector.journaldAccess = true;
  services.vector.settings = {
    enrichment_tables = {
      ipToDomainName = {
        type = "memory";
        ttl = 60;
        inputs = [ "kresdLocalResolvingRecords" ];
      };
      reverseCname = {
        type = "memory";
        ttl = 60;
        inputs = [ "kresdLocalRedirectingRecords" ];
      };
    };
    sources = {
      nftables = {
        type = "exec";
        command = [ readFifoScript nftablesLogFifoPath ];
        mode = "streaming";
      };
      # note :
      # Currently is seems like some sort of buffering is happening
      # dnstap is outputing only every few seconds (1-3).
      # As a result, transforms "enrichedNftablesServicesOut" is able to
      # enrich dst domain name only after a few retry after dns resolutions.
      kresd = {
        type = "dnstap";
        mode = "unix";
        socket_path = dnstapSocketPath;
        multithreaded = true;
        # 464 base 10 -> 720 base 8
        socket_file_mode = 464;
      };
    };
    transforms = {
      kresdLocalClientResponses = {
        type = "filter";
        inputs = [ "kresd" ];
        condition = ''
          .dataType == "Message" &&
          .messageType == "ClientResponse" &&
          .responseAddress == "127.0.0.1"
        '';
      };
      kresdLocalResolvingRecords = {
        type = "remap";
        inputs = [ "kresdLocalClientResponses" ];
        source = ''
          res = {}
          for_each(array!(.responseData.answers || [])) -> |_, answer| {
            if answer.recordType == "A" || answer.recordType == "AAAA" {
              res = set!(res, [answer.rData], answer.domainName)
            }
          }
          return . = res
        '';
      };
      kresdLocalRedirectingRecords = {
        type = "remap";
        inputs = [ "kresdLocalClientResponses" ];
        source = ''
          res = {}

          cnames = []
          lastCnameRData = null
          for_each(array!(.responseData.answers || [])) -> |_, answer| {
            if answer.recordType == "CNAME" {
              lastCnameRData = answer.rData
              cnames = append([answer.domainName], cnames)
            }
          }

          if (lastCnameRData != null) {
            res = set!(res, [lastCnameRData], cnames)
          }
          return . = res
        '';
      };

      parsedNftables = {
        type = "remap";
        inputs = [ "nftables" ];
        source = ''
          if is_string(.message) == false {
            log(".message is not a string", level: "error")
            return . = {}
          }
          parsed_key_values, err = parse_key_value(.message, "=", ",")
          if err != null {
            log("parsed_key_values failed" + (("for : " + .message + " : " + err) ?? ""), level: "error")
            return . = {}
          }
          res = {}
          for_each(parsed_key_values) -> |key,value| {
            res = set!(res, split(key, "."), value)
          }
          return . = res
        '';
      };
      nftablesServices = {
        type = "filter";
        inputs = [ "parsedNftables" ];
        condition = '' .oob.prefix == "nftablesServices" '';
      };
      nftablesServicesOut = {
        type = "filter";
        inputs = [ "nftablesServices" ];
        condition = '' .oob.in == "" && .oob.out != "" '';
      };
      enrichedNftablesServicesOut = {
        type = "remap";
        inputs = [ "nftablesServicesOut" ];
        source = ''
          for_each(${builtins.toJSON config.nixBind.bindings}) -> |address,value| {
            if .ip.daddr.str == address {
              for_each(value) -> |proto,value| {
                for_each(value) -> |serviceName,port| {
                  if get!(., [proto,"dport"]) == to_string(port) {
                    return .nftablesService.dst = serviceName
                  }
                }
              }
            }
          }
          existing, err = get_enrichment_table_record("ipToDomainName", {
            "key": .ip.daddr.str
          })
          if err == null {
            .nftablesService.dst = existing.value

            existing, err = get_enrichment_table_record("reverseCname", {
              "key": .nftablesService.dst
            })
            if err == null {
              .nftablesService.dstReverseCname = existing.value
            }
          }
        '';
      };
    };
    sinks = {
      consoleOutput = {
        type = "console";
        inputs = [ "enrichedNftablesServicesOut" ];
        encoding.codec = "json";
        encoding.json.pretty = true;
      };
    };
  };
}
