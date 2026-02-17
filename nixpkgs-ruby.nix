{ lib
, pkgs
, newScope
}:

let
  applyOverrides = import ./lib/apply-overrides.nix;
  versionComparison = import ./lib/version-comparison.nix;

  mkPkgSet = { pname, versions, overridesFn, packageFn }:
    let
      packageVersions = mkPackageVersions { inherit versions pkgs overridesFn packageFn; };
    in
    lib.mapAttrs' (version: package: { name = if version == "" then pname else "${pname}-${version}"; value = package; }) packageVersions;

  mkPackageVersions = { pkgs, versions, overridesFn, packageFn }:
    let
      overrides = pkgs.callPackage overridesFn { inherit versionComparison; };
      versionedPackageFnWithOverrides = { version, versionSource }:
        let
          pkg =
            pkgs.callPackage packageFn {
              inherit version versionSource;
            };
        in
        applyOverrides {
          inherit (pkgs) lib;
          inherit overrides version pkg;
        };
      packageVersions = builtins.mapAttrs (version: versionSource: versionedPackageFnWithOverrides { inherit version versionSource; }) versions.sources;
      packageAliases = builtins.mapAttrs (alias: version: packageVersions.${version}) versions.aliases;
    in
    packageAliases // packageVersions;

  pkgsets = builtins.mapAttrs
    (name: pkgset: mkPkgSet {
      pname = name;
      inherit (pkgset) versions overridesFn packageFn;
    })
    {
      rubygems = import ./rubygems;
      ruby = import ./ruby;
    };

  allPackages = pkgsets.rubygems // pkgsets.ruby;
  intactPackages = lib.filterAttrs (_: package: lib.isDerivation package && !package.meta.broken) allPackages;
in
lib.makeScope newScope (self: pkgsets // {
  lib = {
    mkRuby =
      { pkgs
      , rubyVersion
      }:
      (pkgsets.ruby pkgs)."ruby-${rubyVersion}";

    readRubyVersionFile = file:
      let
        contents = lib.strings.fileContents file;
        strippedContents = builtins.head (builtins.match "[[:space:]]*(.*)[[:space:]]*" contents);
        segments = lib.strings.splitString "-" strippedContents;
      in
      if builtins.length segments == 1
      then { rubyEngine = "ruby"; version = builtins.head segments; }
      else {
        rubyEngine = builtins.head segments;
        version = builtins.concatStringsSep "-" (builtins.tail segments);
      };

    packageFromRubyVersionFile = { file, system }:
      let
        inherit (self.lib.readRubyVersionFile file) rubyEngine version;
      in
      pkgsets.ruby."${rubyEngine}-${version}";
  };

  inherit allPackages;
  packages = intactPackages;
})
