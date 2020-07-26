# Try to build all reverse dependencies of a given Haskell package.
#
# This is useful if you want to try to make a change in a widely-used Haskell
# package, and you want to figure out all of dependent packages that break.
#
# For instance, this can be used if you want to remove a function from
# a package like conduit, but you're worried that a lot of packages with
# dependencies on conduit will break.
#
# You can use this like the following.  First, you'll need to clone nixpkgs and
# update the Haskell package you want to check.
#
# Then, you can run this:
#
# $ nix-build default.nix --argstr reverseDepsOf conduit --arg nixpkgs 'import /some/path/to/your/edited/nixpkgs {}'
#
# This should build all the Haskell packages with dependencies on conduit.
#
# If you just want to get a list of packages with dependencies on conduit, you
# can use the following command:
#
# $ nix-build default.nix --argstr reverseDepsOf conduit --arg justPrintAllDeps true
#
# This produces a text file with a list of all dependencies of conduit.
#
# --------------------------------------------------------------------
#
# If you would like override a package in the Haskell package set, and then
# find all dependencies of that package, you can use the following code
# as a starting point.  The following overrides "random".
#
# ```nix
# let
#   myHaskellPackageOverlay = self: super: {
#     haskellPackages = super.haskellPackages.override {
#       overrides = hself: hsuper: {
#         random =
#           let newRandomSrc = builtins.fetchGit {
#                 url = "https://github.com/idontgetoutmuch/random.git";
#                 rev = "4bb37cfd588996c55e62ec4f908b8ea7d99a38f6";
#                 ref = "interface-to-performance";
#               };
#           in
#           # Since cabal2nix has a transitive dependency on random, we need to
#           # get the callCabal2nix function from the normal haskellPackages that
#           # is not being overridden.
#           (import <nixpkgs> {}).haskellPackages.callCabal2nix "random" newRandomSrc { };
#       };
#     };
#   };
#
#   nixpkgs = import <nixpkgs> { overlays = [ myHaskellPackageOverlay ]; };
# in
# # This example derivation file is assumed to be in the current directory.  "./default.nix" is
# # the current file you are looking at.
# import ./default.nix {
#   reverseDepsOf = "random";
#   inherit nixpkgs;
# }
# ```
#

{ # Find the reverse dependencies of this Haskell package.  This should be a
  # string matching a Haskell package name.
  reverseDepsOf ? "cryptonite"
, # Whether to create only a list of all the packages with dependencies on
  # "reverseDepsOf". This should be a boolean.
  #
  # `false` means to actually try to build all reverse dependencies of
  # `reverseDepsOf`.
  #
  # `true` means to only output a text file containing a list of packages.
  justPrintAllDeps ? false
, allowBroken ? false
, # This should be nixpkgs pkg set.
  nixpkgs ? import <nixpkgs> {}
, lib ? nixpkgs.lib
, stdenv ? nixpkgs.stdenv
, haskell ? nixpkgs.haskell
, haskellPackages ? nixpkgs.haskellPackages
, buildEnv ? nixpkgs.buildEnv
, runCommand ? nixpkgs.runCommand
}:

let
  inherit (haskell.lib) getHaskellBuildInputs;

  isBroken' = drv:
    let tryEvalRes = builtins.tryEval (
          if !lib.isDerivation drv
          then "not drv"
          else if !(drv ? meta)
          then "no meta"
          else if drv.meta.broken or false
          then "broken"
          else if (drv.meta.hydraPlatforms or lib.platforms.all) == lib.platforms.none
          then "hydraPlatforms none"
          else if (drv.meta.platforms or lib.platforms.all) == lib.platforms.none
          then "platforms none"
          else if !(lib.elem stdenv.hostPlatform.system (drv.meta.platforms or lib.platforms.all))
          then "platform not supported"
          else "not broken"
        );
    in
    if tryEvalRes.success
    then tryEvalRes.value
    else "eval error";

  # A predicate function that returns either `true` or `false` depending on
  # whether the input Haskell package derivation is marked broken.
  #
  # Returns `true` in the following circumstances:
  #
  # - the input derivation fails to evaluate
  # - the input derivation is not actually a derivation
  # - the input derivation does not have a `meta` attribute
  # - the input derivation is actually marked `broken`
  # - the input derivation's `meta.hydraPlatforms` is set to
  #   `lib.platforms.none`.
  #
  # Returns `false` in all other circumstances.
  isBroken = name: drv:
    let isBrokenRes = isBroken' drv;
    in
    if isBrokenRes == "eval error"
    then /* builtins.trace "eval error: ${name}" */ true
    else if isBrokenRes == "not drv"
    then /* builtins.trace "not drv: ${name}" */ true
    else if isBrokenRes == "no meta"
    then /* builtins.trace "no meta: ${name}" */ true
    else if isBrokenRes == "broken"
    then /* builtins.trace "broken: ${name}" */ (if allowBroken then false else true)
    else if isBrokenRes == "hydraPlatforms none"
    then /* builtins.trace "hydraPlatforms none: ${name}" */ true
    else if isBrokenRes == "platforms none"
    then /* builtins.trace "platforms none: ${name}" */ true
    else if isBrokenRes == "platform not supported"
    then builtins.trace "system platform (${stdenv.hostPlatform.system}) not supported for package: ${name}" true
    else if isBrokenRes == "not broken"
    then false
    else abort "unknown return value from isBroken': ${isBrokenRes}";

  # A predicate function that returns either `true` or `false` depending on
  # whether the input derivation has a dependency on `reverseDepsOf`.
  #
  # Returns `false` in the following circumstances:
  #
  # - the input derivation is marked broken
  # - the input derivation doesn't have a `getBuildInputs` attribute (all
  #   Haskell packages should have this)
  # - the input derivation doesn't have a dependency on `reverseDepsOf`
  #
  # Returns `true` in all other circumstances.
  filterReverseDepsOf = name: drv:
    if isBroken name drv
    then false
    else if !(drv ? getBuildInputs)
    then /* builtins.trace "no getBuildInputs: ${name}" */ false
    else
      let haskBuildInputs = getHaskellBuildInputs drv;
          compareName = drv: drv.name == haskellPackages.${reverseDepsOf}.name;
      in
      if !(builtins.any compareName haskBuildInputs)
      then /* builtins.trace "has no dep on ${reverseDepsOf}: ${name}" */ false
      else if builtins.any (drv: isBroken drv.name drv) haskBuildInputs
      then builtins.trace "has dependencies that cannot be built: ${name}" false
      else true;

  # An attribute set of all Haskell packages with a dependency on
  # `reverseDepsOf`.
  reverseDepsAttrs = lib.filterAttrs filterReverseDepsOf haskellPackages;

  # A list of all the attribute values in `reverseDepsAttrs`.
  reverseDepsList = lib.attrValues reverseDepsAttrs;

  # A derivation creating a text file that lists all the packages that have
  # dependencies on `reverseDepsOf`.
  #
  # This is used if you just want a list of all Haskell packages that depend on
  # a given package.
  allReverseDepsDrv =
    let reverseDepsStr =
          lib.concatMapStringsSep
            "\n"
            (haskPkg: "echo ${haskPkg.name} >> $out")
            reverseDepsList;
    in
    runCommand "all-reverse-dependencies-of-${reverseDepsOf}" {} reverseDepsStr;

  # An environment that actually contains all the Haskell packages that depend
  # on the `reverseDepsOf` package.
  #
  # This is used if you want to actually try to build all the packages that
  # depend on the `reverseDepsOf` package.
  allReverseDepsEnv =
    buildEnv {
      name = "all-reverse-dependencies-of-${reverseDepsOf}-env";
      paths = reverseDepsList;
    };
in

if justPrintAllDeps then allReverseDepsDrv else allReverseDepsEnv
