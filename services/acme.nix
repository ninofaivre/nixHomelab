{ kanidm, dataDir }:
{ config, ... }:
{
  security.acme = {
    acceptTerms = true;
    defaults = {
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53"; # not local resolver to check propagation
      email = "admin@6e696e6f.dev";
      credentialFiles."CF_DNS_API_TOKEN_FILE" = config.sops.secrets.cloudflareDnsToken.path;
    };
    certs = {
      "${kanidm.domain}" = {
        # TODO monter {key,chain}.pem dans le service kanidm via systemd-credential
        # et ensuite passer le path via une var d'env. Problème possible :
        # le module nix oblige à define key et chain, peut-être pour en faire quelque chose ?
        postRun =
        let
          inherit (config.systemd.services.kanidm.serviceConfig) User Group;
        in ''
          cp {key,fullchain}.pem ${kanidm.dataDir}
          chown ${User}:${Group} ${kanidm.dataDir}/{key,fullchain}.pem
          chmod 400 ${kanidm.dataDir}/{key,fullchain}.pem
        '';
        # Si je pars en mode systemd-credential il faudra restart au lieu de reload :(
        reloadServices = ["kanidm.service"];
      };
    };
  };
}
