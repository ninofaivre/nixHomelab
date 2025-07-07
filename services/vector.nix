{ nftablesServiceLogFifo, dnsmasqServiceLogFifo }:
{ config, lib, pkgs, unstablePkgs, ... }:
let
  nftablesFifoScript = pkgs.writeShellScript "readFifo" ''
    while :; do
      if [ -p ${nftablesServiceLogFifo} ]; then
        cat ${nftablesServiceLogFifo} | grep .
      fi
      sleep 1
    done
  '';
  dnsmasqScript = pkgs.writeShellScript "dnsmasqJctl" ''
    while :; do
      if [ -p ${dnsmasqServiceLogFifo} ]; then
        cat ${dnsmasqServiceLogFifo} | grep -E '127.0.0.1/[[:digit:]]+ reply [^[:space:]]+ is ([0-9]{1,3}\.){3}[0-9]{1,3}'
      fi
      sleep 1
    done
  '';
in
{
  systemd.services.vector.serviceConfig = {
    ReadOnlyPaths = [ nftablesServiceLogFifo dnsmasqServiceLogFifo ];
    ExecPaths = [ nftablesFifoScript dnsmasqScript ];
  };
  services.vector.enable = true;
  services.vector.package = unstablePkgs.vector;
  services.vector.journaldAccess = true;
  services.vector.settings = {
    enrichment_tables = {
      dnsmasqTable = {
        type = "memory";
        inputs = [ "parsedDnsmasq" ];
        ttl = 10;
        /*
        schema = {
          ip = "string";
          domain = "string";
        };
        */
      };
    };
    sources = {
      nftables = {
        type = "exec";
        command = [ nftablesFifoScript ];
        mode = "streaming";
      };
      dnsmasq = {
        type = "exec";
        command = [ dnsmasqScript ];
        mode = "streaming";
      };
    };
    transforms = {
      parsedDnsmasq = {
        type = "remap";
        inputs = [ "dnsmasq" ];
        source = ''
          . = { "testoa": "coucou" }
        ''/*''
          splitted_message = split!(.message, " ")
          . = {}
          . = set!(., [splitted_message[5]], splitted_message[3])
          log("setting dnsmasqTable to :" + to_string!(.))
        ''*/;
      };
      parsedNftables = {
        type = "remap";
        inputs = [ "nftables" ];
        source = ''
          str, err = to_string(.message)
          if false == assert_eq!(err, null, "Error during to_string(.message): " + err) {
            return null
          } 
          parsed_key_values, err = parse_key_value(str, "=", ",")
          if false == assert_eq!(err, null, "Error during parse_key_value(...): " + err) {
            return null
          }
          . = {}
          for_each(parsed_key_values) -> |key,value| {
            . = set!(., split(key, "."), value)
          }
          .nftablesService = object(.nftablesService) ?? {}
          if .oob.in != "" {
            .nftablesService.src = null
            return null
          }
          for_each(${builtins.toJSON config.nixBind.bindings}) -> |address,value| {
            if .ip.daddr.str == address {
              for_each(value) -> |proto,value| {
                for_each(value) -> |serviceName,port| {
                  if get!(., [proto,"dport"]) == to_string(port) {
                    .nftablesService.dst = serviceName
                    return null
                  }
                }
              }
            }
          }
          existing, err = get_enrichment_table_record("dnsmasqTable", { "key": .ip.daddr.str })
          if (err != null) {
            return null
          }
          .nftablesService.dst = existing
        '';
      };
    };
    sinks = {
      consoleOutput = {
        type = "console";
        inputs = [ /*"parsedNftables"*/ "parsedDnsmasq" ];
        encoding.codec = "json";
        encoding.json.pretty = true;
      };
    };
  };
}
