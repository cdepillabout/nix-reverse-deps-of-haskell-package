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
          if lib.isDerivation drv
          then
            if drv ? meta
            then
              if !(drv.meta ? broken)
              then
                if !(drv.meta ? hydraPlatforms)
                then "not broken"
                else
                  if drv.meta.hydraPlatforms == lib.platforms.none
                  then "hydraPlatforms none"
                  else "not broken"
              else
                if drv.meta.broken
                then "broken"
                else "not broken"
            else "no meta"
          else "not drv"
        );
    in
    if tryEvalRes.success
    then tryEvalRes.value
    else "eval error";

  # A predicate function that returns either `true` or `false` depending on
  # whether the input Haskell package derivation is marked broken.
  #
  # Returns `false` in the following circumstances:
  #
  # - the input derivation fails to evaluate
  # - the input derivation is not actually a derivation
  # - the input derivation does not have a `meta` attribute
  # - the input derivation is actually marked `broken`
  # - the input derivation's `meta.hydraPlatforms` is set to
  #   `lib.platforms.none`.
  #
  # Returns `true` in all other circumstances.
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
    then /* builtins.trace "broken: ${name}" */ true
    else if isBrokenRes == "hydraPlatforms none"
    then /* builtins.trace "hydraPlatforms none: ${name}" */ true
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
    else
      if !(drv ? getBuildInputs)
      then /* builtins.trace "no getBuildInputs: ${name}" */ false
      else
        let haskBuildInputs = getHaskellBuildInputs drv;
            compareName = drv: drv.name == haskellPackages.${reverseDepsOf}.name;
        in
        if builtins.any compareName haskBuildInputs
        then /* builtins.trace "has dep on ${reverseDepsOf}: ${name}" */ true
        else false;

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
