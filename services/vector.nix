{ nftablesServiceLogFifo, dnstapSocketPath }:
{ config, pkgs, unstablePkgs, ... }:
let
  nftablesFifoScript = pkgs.writeShellScript "readFifo" ''
    while :; do
      if [ -p ${nftablesServiceLogFifo} ]; then
        cat ${nftablesServiceLogFifo} | grep .
      fi
      sleep 1
    done
  '';
in
{
  systemd.services.vector.serviceConfig = {
    ReadOnlyPaths = [ nftablesServiceLogFifo ];
    ExecPaths = [ nftablesFifoScript ];
    RuntimeDirectory = "vector";
    RuntimeDirectoryMode = "771";
  };

  services.vector.enable = true;
  services.vector.package = unstablePkgs.vector;
  services.vector.journaldAccess = true;
  services.vector.settings = {
    enrichment_tables = {
      ipToDomainName = {
        type = "memory";
        ttl = 1;
        inputs = [ "parsedKnot-resolver" ];
      };
    };
    sources = {
      # nftables = {
      #   type = "exec";
      #   command = [ nftablesFifoScript ];
      #   mode = "streaming";
      # };
      testoa = {
        type = "file";
        include = [ nftablesServiceLogFifo ];
        fingerprint = {
          strategy = "device_and_inode";
        };
      };
      knot-resolver = {
        type = "dnstap";
        mode = "unix";
        socket_path = dnstapSocketPath;
        socket_file_mode = 511;
      };
    };
    transforms = {
      parsedKnot-resolver = {
        type = "remap";
        inputs = [ "knot-resolver" ];
        source = ''
          if .dataType != "Message" || .messageType != "ClientResponse" || .responseAddress != "127.0.0.1" {
            return . = {}
          }
          res = {}
          for_each(array!(.responseData.answers || [])) -> |_, answer| {
            if answer.recordType == "A" || answer.recordType == "AAAA" {
              res = set!(res, [answer.rData], answer.domainName)
            }
          }
          return . = res
        '';
      };
      parsedTestoa = {
        type = "remap";
        inputs = [ "testoa" ];
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
          return res
        '';
      };
    #   parsedNftables = {
    #     type = "remap";
    #     inputs = [ "nftables" ];
    #     source = ''
    #       str, err = to_string(.message)
    #       if false == assert_eq!(err, null, "Error during to_string(.message): " + err) {
    #         return null
    #       } 
    #       parsed_key_values, err = parse_key_value(str, "=", ",")
    #       if false == assert_eq!(err, null, "Error during parse_key_value(...): " + err) {
    #         return . = {}
    #       }
    #       . = {}
    #       for_each(parsed_key_values) -> |key,value| {
    #         . = set!(., split(key, "."), value)
    #       }
    #       .nftablesService = object(.nftablesService) ?? {}
    #       if .oob.in != "" {
    #         return .nftablesService.src = null
    #       }
    #       for_each(${builtins.toJSON config.nixBind.bindings}) -> |address,value| {
    #         if .ip.daddr.str == address {
    #           for_each(value) -> |proto,value| {
    #             for_each(value) -> |serviceName,port| {
    #               if get!(., [proto,"dport"]) == to_string(port) {
    #                 return .nftablesService.dst = serviceName
    #               }
    #             }
    #           }
    #         }
    #       }
    #       existing, err = get_enrichment_table_record("ipToDomainName", {
    #         "key": .ip.daddr.str
    #       })
    #       if err == null {
    #         .nftablesService.dst = existing.value
    #       }
    #     '';
    #   };
    };
    sinks = {
      consoleOutput = {
        type = "console";
        inputs = [ "testoa" ];
        encoding.codec = "json";
        encoding.json.pretty = true;
      };
    };
  };
}
