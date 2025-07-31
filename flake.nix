{
  description = "Dev shell for Zig + OpenSSL on NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }: {
    devShells = {
      x86_64-linux = let
        system = "x86_64-linux";
        pkgs = import nixpkgs { inherit system; };
      in {
        default = pkgs.mkShell {
          name = "zig-openssl-shell";
          packages = [
            pkgs.zig
            pkgs.openssl
            pkgs.pkg-config
          ];

          shellHook = ''
            echo "Zig + OpenSSL dev shell ready."
            export C_INCLUDE_PATH=${pkgs.openssl.dev}/include
            export LIBRARY_PATH=${pkgs.openssl.out}/lib
          '';
        };
      };
    };
  };
}

