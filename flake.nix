{
  description = "lush - a Lua powered shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };
        rust = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" "clippy" "rustfmt" ];
          targets = [ 
            "aarch64-apple-darwin" 
            "x86_64-apple-darwin" 
            "x86_64-pc-windows-msvc" 
            "aarch64-pc-windows-msvc" 
            "x86_64-unknown-linux-musl" 
            "aarch64-unknown-linux-musl" 
          ];
        };
      in
      {
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = "lush";
          version = "0.1.0";
          src = ./.;

          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = with pkgs; [
            pkg-config
            cmake
          ];

          buildInputs = with pkgs; [
            lua5_4
            openssl
            libiconv
          ];

          checkFlags = [ "--skip=repl" ];

          meta = with pkgs.lib; {
            description = "a Lua-powered shell with native Unix commands and embedded POSIX sh";
            homepage = "https://github.com/everett-k/lush";
            license = licenses.gpl3Only;
            maintainers = [];
            mainProgram = "lush";
            platforms = platforms.unix;
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            rust
            pkg-config
            cmake
            lua5_4
            openssl
            openssl.dev
            libiconv
            cargo-watch
            cargo-edit
            cargo-expand
            ripgrep
            jq
            act
            nodejs
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            pkgs.glibc
          ];

          RUST_BACKTRACE = 1;
          RUST_LOG = "debug";

          # Define a custom environment variable or function for Procursus setup
          PROCURSUS_BOOTSTRAP = "${./procursus-bootstrap.sh}";

          shellHook = ''
            export CARGO_HOME="$HOME/.cargo"
            export PATH="$CARGO_HOME/bin:$PATH"
            
            setup_procursus() {
              echo "Setting up Procursus environment..."
              sudo bash "$PROCURSUS_BOOTSTRAP"
            }
            
            export -f setup_procursus
            echo "Procursus environment tool: run 'setup_procursus'"
          '';
        };
      }
    );
}
