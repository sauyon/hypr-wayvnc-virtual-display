{
  description = "On-demand Hyprland headless output for wayvnc, lifecycled by client connect/disconnect";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forSystems = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in
    {
      packages = forSystems (pkgs: rec {
        hypr-wayvnc-virtual-display = pkgs.callPackage ./nix/package.nix { };
        default = hypr-wayvnc-virtual-display;
      });

      homeManagerModules.default = ./nix/module.nix;

      checks = forSystems (pkgs: {
        package = self.packages.${pkgs.system}.default;
      });

      formatter = forSystems (pkgs: pkgs.nixfmt);
    };
}
