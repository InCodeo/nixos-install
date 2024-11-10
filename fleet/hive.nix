{
  meta.nixpkgs = import <nixpkgs> {};
  "nixos-client-1" = { config, pkgs, ... }: {  # Added 'config' parameter here
    # Import your common configuration
    imports = [
      ./common.nix
    ];
    
    # Define required NixOS configuration inline
    fileSystems = {
      "/" = {
        device = "/dev/nvme0n1p2";
        fsType = "ext4";
      };
      "/boot" = {
        device = "/dev/nvme0n1p1";
        fsType = "vfat";
      };
    };
    
    # Bootloader and Surface Pro specific configuration
    boot = {
      loader.systemd-boot.enable = true;
      loader.efi.canTouchEfiVariables = true;
      kernelPackages = pkgs.linuxPackages_latest;
      kernelParams = [
        "surface_acpi=off"
        "mem_sleep_default=deep"
      ];
      initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
      initrd.kernelModules = [ "dm-snapshot" ];
    };
    
    # Network configuration
    networking = {
      hostName = "nixos-client-1";
      networkmanager.enable = true;
      firewall = {
        enable = true;
        allowedTCPPorts = [ 22 9000 3150 ];
        trustedInterfaces = [ "tailscale0" ];
        # Fixed the config reference for Tailscale
        allowedUDPPorts = [ 41641 9 ]; # Default Tailscale port and WoL magic packet
      };
    };

    # Rest of configuration remains the same...
    time.timeZone = "Australia/Sydney";
    i18n = {
      defaultLocale = "en_AU.UTF-8";
      extraLocaleSettings = {
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
    };

    # Enable the X11 windowing system
    services.xserver = {
      enable = true;
      layout = "us";
      xkbVariant = "";
    };

    # Enable KDE Plasma 6
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;

    # Configure console keymap
    console.useXkbConfig = true;

    # Enable CUPS to print documents
    services.printing.enable = true;

    # Sound configuration
    sound.enable = true;
    hardware.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    # Enable firmware updates
    services.fwupd.enable = true;

    # User configuration
    users.users.homelab = {
      isNormalUser = true;
      description = "Home Lab User";
      extraGroups = [ "networkmanager" "wheel" "audio" "video" "docker" ];
      packages = with pkgs; [
        kdePackages.kate
      ];
      initialPassword = "changeme";
      shell = pkgs.zsh;
    };

    # Enable Firefox
    programs.firefox.enable = true;

    # Allow unfree packages
    nixpkgs.config.allowUnfree = true;

    # Basic system packages
    environment.systemPackages = with pkgs; [
      wget
      vim
      git
      tailscale
      iptsd
      libwacom
      pciutils
      usbutils
      curl
      zsh
      tilix
      docker-compose  # Added Docker Compose
      ethtool    # Added for WoL support
    ];

    # Set zsh as default shell system-wide
    users.defaultUserShell = pkgs.zsh;
    users.users.root.shell = pkgs.zsh;
    
    # Configure zsh
    programs.zsh = {
      enable = true;
      ohMyZsh = {
        enable = true;
        plugins = [ "git" "docker" "sudo" ];
        theme = "robbyrussell";
      };
    };

    # SSH Configuration
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = true;
        PermitRootLogin = "yes";
      };
    };

    # Deployment configuration
    deployment = {
      targetHost = "nixos-client-1.tailec10ee.ts.net";
      targetUser = "root";
    };

    # System version
    system.stateVersion = "24.05";

    # Power management settings
    powerManagement = {
      enable = true;
      powertop.enable = true;
      cpuFreqGovernor = "performance";
    };

    # Modified WoL service with error handling
    systemd.services.enable-wol = {
      description = "Enable Wake-on-LAN for network interface";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Add error handling to prevent service failure
        ExecStart = "${pkgs.bash}/bin/bash -c '\
          for interface in $(${pkgs.iproute2}/bin/ip link show | grep -v lo | awk -F: \'/^[0-9]+:/ {print $2}\' | tr -d \" \"); do \
            ${pkgs.ethtool}/bin/ethtool -s $interface wol g || true; \
          done'";
      };
    };

    # Network interface configuration - make it more generic
    networking.interfaces = {
      # Remove specific interface name and let NetworkManager handle it
      # enp0s13f0u1c2 = {
      #   useDHCP = true;
      #   wakeOnLan.enable = true;
      #   wakeOnLan.policy = [ "magic" ];
      # };
    };

    # Disable sleep and hibernation
    services.logind = {
      lidSwitch = "ignore";
      extraConfig = ''
        HandleSuspendKey=ignore
        HandleHibernateKey=ignore
        HandleLidSwitch=ignore
        IdleAction=ignore
      '';
    };

    # Additional sleep prevention configuration
    systemd.sleep.extraConfig = ''
      AllowSuspend=no
      AllowHibernation=no
      AllowSuspendThenHibernate=no
      AllowHybridSleep=no
    '';

    # Enable Docker
    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
    };

    # Portainer configuration
    virtualisation.oci-containers.containers = {
      portainer = {
        image = "portainer/portainer-ce:latest";
        ports = [ "9000:9000" ];
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock"
          "portainer_data:/data"
        ];
        autoStart = true;
      };
      
      homepage = {
        image = "ghcr.io/gethomepage/homepage:latest";
        ports = [ "3150:3000" ];
        environment = {
          PUID = "1000";  # We'll need to adjust this to match your homelab user
          PGID = "1000";  # Same here
        };
        volumes = [
          "/var/lib/homepage/config:/app/config"
          "/var/run/docker.sock:/var/run/docker.sock:ro"
        ];
        autoStart = true;
      };
    };

    # Homepage dashboard directory and config management
    systemd.tmpfiles.rules = [
      "d /var/lib/homepage 0755 root root -"
      "d /var/lib/homepage/config 0755 root root -"
    ];

    environment.etc = {
      "homepage/settings.yaml" = {
        source = ./homepage/settings.yaml;
        target = "/var/lib/homepage/config/settings.yaml";
      };
      "homepage/services.yaml" = {
        source = ./homepage/services.yaml;
        target = "/var/lib/homepage/config/services.yaml";
      };
      "homepage/widgets.yaml" = {
        source = ./homepage/widgets.yaml;
        target = "/var/lib/homepage/config/widgets.yaml";
      };
      "homepage/docker.yaml" = {
        source = ./homepage/docker.yaml;
        target = "/var/lib/homepage/config/docker.yaml";
      };
    };

  };
}