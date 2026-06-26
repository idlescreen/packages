{
  description = "UberMetroid packages repository and Nix Flake distribution";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forEachSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f (import nixpkgs { inherit system; }));
    in {
      packages = forEachSystem (pkgs: {
        # Placeholders/templates for packages.
        # When moving code repositories to nix, actual flake outputs can be linked here.
        default = pkgs.hello;
      });
    };
}
