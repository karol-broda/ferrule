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
          llvmPackages = pkgs-unstable.llvmPackages_21;
          # override stdenv to use gcc/libstdc++ instead of clang/libc++
          # this matches how the llvm libraries are built
          gccStdenv = pkgs-unstable.overrideCC pkgs-unstable.stdenv pkgs-unstable.gcc;
        in
        gccStdenv.mkDerivation {
          name = "zig-llvm-devshell";

          buildInputs = [
            pkgs-unstable.zig
            pkgs-unstable.bun
            llvmPackages.llvm
            llvmPackages.libllvm
            llvmPackages.clang
            pkgs-unstable.gcc.cc.lib
            pkgs-unstable.ncurses
            pkgs-unstable.zlib
            pkgs.nodejs_22
          ];

          shellHook = ''
            export LLVM_SYS_180_PREFIX="${llvmPackages.llvm.dev}"
            export LLVM_LIBDIR="${llvmPackages.libllvm.lib}/lib"
            if [ -n "$PS1" ]; then
              echo "zig: $(zig version)"
              echo "llvm: $(llvm-config --version)"
              echo "clang: $(clang --version | head -n1)"
              echo "LLVM_LIBDIR: $LLVM_LIBDIR"
            fi
          '';
        };
    in
    {
      devShells.x86_64-linux.default = mkShellFor "x86_64-linux";
      devShells.aarch64-linux.default = mkShellFor "aarch64-linux";
      devShells.x86_64-darwin.default = mkShellFor "x86_64-darwin";
      devShells.aarch64-darwin.default = mkShellFor "aarch64-darwin";
    };
}

