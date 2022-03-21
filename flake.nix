{
  description = "evdev KVM software";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixpkgs-unstable;
    flake-utils.url = github:numtide/flake-utils;
    zig-overlay.url = github:arqv/zig-overlay;
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      rec {
        defaultPackage = pkgs.stdenv.mkDerivation {
          name = "evdev-proxy";

          nativeBuildInputs = with pkgs; [
            pkg-config
            zig-overlay.packages.${system}.master.latest
          ];

          src = ./.;

          buildPhase = ''
            # Set Zig global cache directory
            export XDG_CACHE_HOME="$TMPDIR/zig-cache/"
            zig build
          '';
          installPhase = ''
            zig build install --prefix $out
          '';

          meta = { };
        };
      }
    );
}
