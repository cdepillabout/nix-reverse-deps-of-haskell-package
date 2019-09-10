# Reverse Dependencies of Haskell Packages

[![Build Status](https://secure.travis-ci.org/cdepillabout/nix-reverse-deps-of-haskell-package.svg)](http://travis-ci.org/cdepillabout/nix-reverse-deps-of-haskell-package)
[![BSD3 license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

This repository provides a Nix file that allows you to find and build all
reverse dependencies of a given Haskell package.

This is useful if you want to make a change to a widely-used Haskell package
and see which reverse dependencies break.

For instance, if you want to remove a method from
[`conduit`](http://hackage.haskell.org/package/conduit), this can be easily
used to build all Haskell packages with transitive dependencies on `conduit`
and see what breaks.

## Usage

Usage instructions are described at the top of [`default.nix`](./default.nix).

## Other Methods

Normally, the tool [`nix-review`](https://github.com/Mic92/nix-review)
is used to rebuild all reverse-dependencies of a file in `nixpkgs`.  However,
`nix-review` doesn't work with the Haskell package set in `nixpkgs`, so this
repository is necessary.
