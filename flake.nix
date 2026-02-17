{
  description = "mkRuby to build a version of Ruby";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.flake-compat.url = "github:edolstra/flake-compat";
  inputs.flake-compat.flake = false;

  nixConfig = {
    extra-substituters = "https://nixpkgs-ruby.cachix.org";
    extra-trusted-public-keys = "nixpkgs-ruby.cachix.org-1:vrcdi50fTolOxWCZZkw0jakOnUI1T19oYJ+PRYdK4SM=";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , ...
    }:
    {
      templates.default = {
        path = ./template;
        description = "A standard Nix-based Ruby project";
        welcomeText = ''
          Usage:

          $ nix develop

          See https://github.com/bobvanderlinden/nixpkgs-ruby for more information.
        '';
      };

      overlays = import ./overlays.nix;
    }
    // flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          self.overlays.default
        ];
        config.permittedInsecurePackages = [
          "openssl-1.1.1w"
        ];
      };
      versionComparison = import ./lib/version-comparison.nix;
    in
    {
      legacyPackages = pkgs;
      packages = pkgs.nixpkgs-ruby;

      checks =
        let
          lib = nixpkgs.lib;
          mkTest = { name, command, env ? { }, nativeBuildInputs ? [ ] }:
            pkgs.runCommand name ({ inherit nativeBuildInputs; } // env) command;
          rubyPackages = pkgs.nixpkgs-ruby.ruby;
          rubyTestAttrs = lib.concatMapAttrs
            (rubyName: ruby:
              let
                rubyVersion = nixpkgs.lib.removePrefix "ruby-" rubyName;
              in
              {
                "${rubyName}-puts-ok" = {
                  nativeBuildInputs = [
                    ruby
                  ];
                  command = ''
                    ruby -e 'puts "ok"' > $out
                  '';
                };
                "${rubyName}-jemalloc" = {
                  nativeBuildInputs = [
                    (ruby.override { jemallocSupport = true; })
                  ];
                  command = ''
                    ruby -e 'puts "ok"' > $out
                  '';
                };
                "${rubyName}-mkRuby" = {
                  nativeBuildInputs = [
                    (self.lib.mkRuby {
                      inherit pkgs rubyVersion;
                    })
                  ];
                  command = ''
                    ruby -e 'puts "ok"' > $out
                  '';
                };
              } // (lib.optionalAttrs (with versionComparison rubyVersion; greaterOrEqualTo "2.4") {
                # Ruby <2.4 only supports openssl 1.0 and not openssl1.1. openssl 1.0 is not supported by nixpkgs
                # anymore, so we will not support it here.
                "${rubyName}-openssl" = {
                  nativeBuildInputs = [
                    ruby
                  ];
                  command = ''
                    ruby -e 'require "openssl"; puts OpenSSL::OPENSSL_VERSION' > $out
                  '';
                };
              }) // (lib.optionalAttrs (with versionComparison rubyVersion; greaterOrEqualTo "2.2") {
                "${rubyName}-bundlerEnv" =
                  let
                    gems = pkgs.bundlerEnv {
                      name = "gemset";
                      inherit ruby;
                      gemfile = ./tests/bundlerEnv/Gemfile;
                      lockfile = ./tests/bundlerEnv/Gemfile.lock;
                      gemset = ./tests/bundlerEnv/gemset.nix;
                      groups = [ "default" "production" "development" "test" ];
                    };
                  in
                  {
                    nativeBuildInputs = [
                      self.packages.${pkgs.system}.${rubyName}
                      gems
                    ];
                    command = ''
                      ruby -e 'require "foobar"; say' > $out
                    '';
                  };
              })
            )
            rubyPackages;

          testAttrs = rubyTestAttrs // {
            packageFromRubyVersionFileWithoutEngine =
              let
                ruby = self.lib.packageFromRubyVersionFile {
                  file = ./tests/ruby-version-without-engine;
                  inherit system;
                };
              in
              {
                nativeBuildInputs = [
                  ruby
                ];
                command = ''
                  ruby -e 'puts RUBY_VERSION' > $out
                '';
              };
            packageFromRubyVersionFileWithEngine =
              let
                ruby = self.lib.packageFromRubyVersionFile {
                  file = ./tests/ruby-version-with-engine;
                  inherit system;
                };
              in
              {
                nativeBuildInputs = [
                  ruby
                ];
                command = ''
                  ruby -e 'puts RUBY_VERSION' > $out
                '';
              };
          };
        in
        lib.mapAttrs
          (name: testAttrs:
            mkTest ({
              inherit name;
            } // testAttrs)
          )
          testAttrs;

      devShells = {
        # The shell for editing this project.
        default = pkgs.mkShell {
          nativeBuildInputs = with pkgs;
            [
              nixpkgs-fmt
            ];
        };
      };

      apps.update = {
        type = "app";
        program =
          let
            inherit (builtins) map attrNames getFlake concatStringsSep filter;
            inherit (nixpkgs.lib) mapAttrsToList filterAttrs;
            pkgsetsToUpdate = filterAttrs (name: pkgset: pkgset ? updater) { inherit (pkgs.nixpkgs-ruby) ruby rubygems; };
            updateCommand = name: pkgset:
              ''
                echo "Updating ${name}..."
                (cd ${name} && ${pkgs.callPackage pkgset.updater { }}/bin/update)
              '';
            updateCommands = mapAttrsToList updateCommand pkgsetsToUpdate;
            script = pkgs.writeScript "update" ''
              #!${pkgs.bash}/bin/bash
              set -o errexit
              ${concatStringsSep "\n" updateCommands}
            '';
          in
          "${script}";
      };
    });
}
