# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, lanIp, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.enableContainers = true;

  # Set your time zone.
  time.timeZone = "Europe/Paris";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "fr";
  };

  # Enable CUPS to print documents.
  # services.printing.enable = true;
  powerManagement = {
    cpuFreqGovernor = lib.mkDefault "powersave";
    enable = false;
    powertop.enable = true;
  };

  services.tlp = {
    enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.nino = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [ vim hwinfo zfs parted pciutils htop powertop age sops ];
    openssh = {
      authorizedKeys = {
        keys = [
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCfMKHSVNtFyMdg3ylKLVt/Tnf0jdxSqGGaRWP1StbMg7IMcC1xFk8ac8R8LLSOcZk5Ba8e5I+D2Ckv61WarhtKeNYLHSY3Xe3MlcJ10peatP8SP5lY5YSsryHc+dcbtjTFOpH14+sPdzZMswpIsM2c8aqYO0NsgVTflUv6vpzKmPD/LvB3Wl51lxDsNzic6MBE/wnPNJiGsg/HcBzHzuUlReF8RMUxkXKBmMpqDCw7nRn9MR04C5HXdx5Z+qh6p3+Rylb1TXLVnX3wTFATnZwMYtaonOSrNWqn1/auZrzD0R0llUTPbzu6adKV6ejkb9nwYsiYqHOvinLdURBCzufZ nino@WORKSTATION-NINO-ZORINOS"
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCy1Zx1nHYKfuwC0ImjMYMBlyJlyihe+Qs2PRaz24MahX9g18O+hkc+sn8Rt3+bKA2MUEB3F6dxk4NL69cU+2piUx2O5qenRxC485AA6lHBi2nWx1yRgJpbp2Botmwm/mNZbMsOiXKjTLpiiKMWPw7QO91RT1X8qPb/C44RU8+QpHXDsfXvrdboyZQSHgxFQ/kJ3HFpca4R4s4D/UmnlnQmQ7kyJ+Iz0BXHp8eiEYtKr5atJXQwTTnBkB43tbLni62VkxDND3+8AEYkwHBWoMjD5H/BaQ86lkU29h6P6hXo0MYy1dOIcJhSJxb6PeYUCX+AuW+SzHk35hMSKwKPWNmGFiy1Cb06XbpFlUj4q5tXrx983ruzVZ1ufeTqUWsbY2XIffEFM3LBnpt0x+AflElatHeRN7x1534XbmjBTFJRFixe59b1bEk0Zhwvgrj1gjttY4rZXo8rnGjbdZQ8EbCubFY1BPS0V2qe01QS18J/CC323KzbS1CXIwXwu0g06H8= nino@ninoArchLinuxDesktop"
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDBOIKEitIBDyliVBgIUmuYF9yL7RZWkSO0nizCcyHpTe9esH+1jwCogT1d+W5vPvYBLMBrBMVqoX1drE7DyOQ5dqM6pPUe3TnLiG2NFlzO4iq0BZM5e4QcHlbxit9SCT8MRfl0vH6rB0xVZltBB+1pe4Oi3QyWouTADQwxxD9zj06ojhzT5P2Vfyk1UR5iBKnl6IbwBjkRFxx88Kw9eomEZKNt1hb8kzfkJWLYVuL6R+Xma2PKITZ31gfmPicOlzB2vy/ICWleD51Ai7tLZNmcU1JzRxUW8NxFia69aZHa5kHV0OVwRW91nb9WgY67e0XpgrLcgN2jkx+TW4IvYvxLyugVwgtxa9jhezC/xTyVzw9HS7d8g4KCda04VJSjNt1KkAglePSU4SMZsQJAg9E7wM7Y2im4Mnra+IMptP3ATHI61UzM+45XaAj5YHIwFf3twJ/FfIo0dH2c/yagdy5feeTsloWoqaufp351CyFMHRqXzzIPmaAyNGmbIE2yStM= nino@archlinuxNinoLaptop"
        ];
      };
    };
  };

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
  ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  programs.vim.defaultEditor = true;
  programs.vim.enable = true;
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  bindings."${lanIp}"."ssh" = 22;
  services.openssh = {
    enable = true;
    listenAddresses = [
      {
        addr = lanIp;
        port = config.bindings."${lanIp}"."ssh";
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

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.05"; # Did you read the comment?
}

