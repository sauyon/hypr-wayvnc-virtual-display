{ config, lib, pkgs, ... }:
let
  cfg = config.services.hypr-wayvnc-virtual-display;
in
{
  options.services.hypr-wayvnc-virtual-display = {
    enable = lib.mkEnableOption "the on-demand Hyprland headless output for wayvnc";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      description = "The hypr-wayvnc-virtual-display package providing wayvnc-on-demand.";
    };

    headless.mode = lib.mkOption {
      type = lib.types.str;
      default = "1920x1080@60";
      example = "2560x1440@60";
      description = "Resolution and refresh of the headless output, as accepted by `hyprctl keyword monitor`.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    systemd.user.services.wayvnc-on-demand = {
      Unit = {
        Description = "On-demand Hyprland headless output for wayvnc";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" "wayvnc.service" ];
        Wants = [ "wayvnc.service" ];
      };
      Service = {
        Environment = [ "HEADLESS_MODE=${cfg.headless.mode}" ];
        ExecStart = "${cfg.package}/bin/wayvnc-on-demand";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
