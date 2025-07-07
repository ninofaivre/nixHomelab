{ ... }:
{
  services.acns = {
    enable = true;
    unixSocketAccessGroupName = "acnsAccessKresd";
    settings = {
      accessControl = {
        inet = {
          filter = [
            "api.github.com.v4"
            "api.github.com.v6"
          ];
        };
      };
    };
  };
}
