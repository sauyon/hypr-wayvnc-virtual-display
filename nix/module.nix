{ config, lib, pkgs, ... }:
let
  cfg = config.services.hypr-wayvnc-virtual-display;
in
{
  options.services.hypr-wayvnc-virtual-display = {
    enable = lib.mkEnableOption "the persistent Hyprland headless output and wayvnc output pinning";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      description = "The hypr-wayvnc-virtual-display package providing wayvnc-headless and wayvnc-output-pin.";
    };

    headless = {
      mode = lib.mkOption {
        type = lib.types.str;
        default = "1920x1080@60";
        example = "2560x1440@60";
        description = "Resolution and refresh of the headless output, as accepted by `hyprctl keyword monitor`.";
      };

      mirrorOutput = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "DP-5";
        description = ''
          Optional physical Hyprland output to mirror onto the headless output.
          When set, the physical display drives the framebuffer at its native
          resolution and the headless output serves a downscaled copy to wayvnc.
          When null, the headless output is standalone.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    systemd.user.services.wayvnc-headless = {
      Unit = {
        Description = "Persistent Hyprland headless output for wayvnc";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment =
          [
            "HEADLESS_MODE=${cfg.headless.mode}"
          ]
          ++ lib.optional (cfg.headless.mirrorOutput != null)
            "MIRROR_OUTPUT=${cfg.headless.mirrorOutput}";
        ExecStart = "${cfg.package}/bin/wayvnc-headless";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.wayvnc-output-pin = {
      Unit = {
        Description = "Pin wayvnc to a Hyprland headless output across hotplug events";
        PartOf = [ "graphical-session.target" "wayvnc.service" ];
        After = [ "wayvnc.service" "wayvnc-headless.service" ];
        BindsTo = [ "wayvnc.service" ];
        Requires = [ "wayvnc-headless.service" ];
      };
      Service = {
        EnvironmentFile = "-%t/hypr-wayvnc-virtual-display.env";
        ExecStart = "${cfg.package}/bin/wayvnc-output-pin";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
