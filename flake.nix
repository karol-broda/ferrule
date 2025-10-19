{
  description = "zig devshell flake";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-25.05";
    };
    nixpkgs-unstable = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable }:
    let
      mkShellFor = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
        in
        pkgs.mkShell {
          packages = [
            pkgs-unstable.zig
          ];

          shellHook = ''
            if [ -n "$PS1" ]; then
              echo "zig: $(zig --version)"
            fi
          '';
        };
    in
    {
      # explicit nested outputs per system
      devShells.x86_64-linux.default = mkShellFor "x86_64-linux";
      devShells.aarch64-linux.default = mkShellFor "aarch64-linux";
      devShells.x86_64-darwin.default = mkShellFor "x86_64-darwin";
      devShells.aarch64-darwin.default = mkShellFor "aarch64-darwin";
    };
}

