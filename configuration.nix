{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking = {
    hostName = "nixos-manager";
    networkmanager = {
      enable = true;
    };
    # Fallback DNS servers
    nameservers = [ "8.8.8.8" "1.1.1.1" ];
    # Enable wireless support via wpa_supplicant
    wireless.enable = false;  # Disable wpa_supplicant as we're using NetworkManager
  };

  # Time zone and locale settings
  time.timeZone = "Australia/Sydney";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_AU.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_AU.UTF-8";
    LC_IDENTIFICATION = "en_AU.UTF-8";
    LC_MEASUREMENT = "en_AU.UTF-8";
    LC_MONETARY = "en_AU.UTF-8";
    LC_NAME = "en_AU.UTF-8";
    LC_NUMERIC = "en_AU.UTF-8";
    LC_PAPER = "en_AU.UTF-8";
    LC_TELEPHONE = "en_AU.UTF-8";
    LC_TIME = "en_AU.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;
    
    # Enable the KDE Plasma Desktop Environment.
    displayManager.sddm.enable = true;
    desktopManager.plasma6.enable = true;
    
    # Configure keymap
    xkb = {
      layout = "us";
      variant = "";
    };
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Tailscale configuration
  services.tailscale.enable = true;

  # User configuration
  users.users.admin = {
    isNormalUser = true;
    description = "Management Admin";
    extraGroups = [ "networkmanager" "wheel" ];
    initialPassword = "changeme";
    packages = with pkgs; [
      kdePackages.kate
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Management tools and basic system packages
  environment.systemPackages = with pkgs; [
    wget
    vim
    git
    tailscale
    colmena
    htop
    tmux
    iftop
    nmap
    curl
    pciutils
    usbutils
    dmidecode
    bind  # for dig/nslookup
    inetutils  # for ping, etc.
    ethtool
    networkmanager
    zsh
    oh-my-zsh
  ];

  # ZSH Configuration
  programs.zsh = {
    enable = true;
    ohMyZsh = {
      enable = true;
      plugins = [ "git" "docker" "sudo" ];
      theme = "robbyrussell";
    };
    shellInit = ''
      # Define hello world function
      function hello() {
        echo "Hello, NixOS World!"
      }
    '';
  };

  # Set ZSH as default shell for root
  users.defaultUserShell = pkgs.zsh;
  users.users.root.shell = pkgs.zsh;

  # SSH Configuration
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;  # Will be disabled after initial setup
      PermitRootLogin = "yes";       # Will be disabled after initial setup
    };
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 
      22    # SSH
    ];
    # Allow Tailscale traffic
    trustedInterfaces = [ "tailscale0" ];
    # Allow incoming connections through Tailscale
    allowedUDPPorts = [ config.services.tailscale.port ];
  };
  # Hyper-V specific configuration
  virtualisation.hypervGuest.enable = true;
  services.qemuGuest.enable = true;

  system.stateVersion = "24.05";
}
