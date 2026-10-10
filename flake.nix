# terminal-browser-agent — rushi ext flake (Mode B).
#
# This is a tool-only repo: one rushi tool (terminal-browser), shipped as
# a POSIX sh wrapper (bin/tb) plus a Node helper (bin/cdp-download.mjs)
# plus an on-demand procedure doc (docs/procedure.md). There is no cargo
# build, so the package is a plain copy of the tool source dir into the
# tool $out contract — not a buildCrate build. A consumer wires the
# exposed package into rushi.external_tools (see the kernel flake's
# lib/mk-rushi.nix and docs/reference/nix/nix-flake-module.md §5).
#
# $out contract (tool, ext-flake-authoring.md §2 / §8 P1):
#   $out/terminal-browser/tool.toml
#   $out/terminal-browser/bin/tb
#   $out/terminal-browser/bin/cdp-download.mjs
#   $out/terminal-browser/docs/procedure.md
#
# The consumer's copy step is `cp -rL "$src/." <pkg>/tools/`, so this
# lands as <pkg>/tools/terminal-browser/…. meta.rushi.entry names the
# entry dir so lib.mkRushi fills the consumer's
# [paths] extension_tool_paths with "tools/terminal-browser" at eval
# time (issue #13) instead of a second hand-typed copy.
{
  description = "terminal-browser-agent — terminal-browser web-browsing tool for rushi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      # Mirror the kernel flake's supportedSystems (ext-flake-authoring.md
      # §3): aarch64-darwin is a first-class rushi platform. This flake
      # only copies files (no build), so all three are safe.
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      pkgLib = nixpkgs.lib;

      # The tool package for one system. No build step: a bare copy of
      # the tool source dir into the tool $out contract.
      #
      # Two nixpkgs gotchas (ext-flake-authoring.md §3):
      #  * `version` must accompany `pname` — with only `pname`, stdenv
      #    does not synthesize `name` and derivationStrict dies with
      #    "attribute 'name' missing".
      #  * a bare-copy derivation still needs a `src` for unpackPhase
      #    ("variable $src or $srcs should point to the source"); use a
      #    placeholder via writeTextFile.
      toolPkg =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.stdenv.mkDerivation {
          pname = "terminal-browser-tool";
          version = "0.1.0";

          src =
            pkgs.writeTextFile {
              name = "terminal-browser-tool-src";
              destination = "/placeholder";
              text = "";
            };

          # Copy the whole tool source dir (tool.toml, bin/, docs/) under
          # the entry dir name. `tb` resolves the sibling Node helper with
          # `dirname "$0"`, so bin/ must stay intact next to it.
          installPhase = ''
            mkdir -p $out/terminal-browser
            cp -rL ${self}/tools/terminal-browser/. $out/terminal-browser/
            # route resolves command "tb" to <tool>/bin/tb and execs it
            # directly, so guarantee the store copy keeps the exec bit.
            chmod +x $out/terminal-browser/bin/tb
          '';

          # Issue #13: declare the tool entry dir. lib.mkRushi reads
          # meta.rushi.entry at eval time and fills the consumer's
          # [paths] extension_tool_paths with "tools/terminal-browser".
          # The meta value is the entry dir name, not a config path.
          meta = {
            description = "terminal-browser tool for rushi";
            rushi = { entry = "terminal-browser"; };
          };
        };

      # Per-system package attrset exposed under the flake's top-level
      # `packages` key (standard shape: `nix build .` resolves
      # packages.<host>.default; a consumer reads
      # extFlake.packages.<system>."terminal-browser").
      packagesFor =
        system:
        let
          tb = toolPkg system;
        in
        {
          terminal-browser = tb;
          default = tb;
        };
    in
    {
      packages = pkgLib.genAttrs supportedSystems packagesFor;

      # Producer-side gate (ext-flake-authoring.md §8 P1): assert the
      # tool contract layout before a consumer wires the package in.
      checks = pkgLib.genAttrs supportedSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          tb = toolPkg system;
        in
        {
          tool-layout =
            pkgs.stdenvNoCC.mkDerivation {
              pname = "terminal-browser-tool-layout";
              version = "0";
              nativeBuildInputs = [ tb ];
              dontUnpack = true;
              dontConfigure = true;
              dontBuild = true;
              # Assert the P1 tool contract layout, then produce $out so
              # the derivation succeeds. A failed `test` aborts the build.
              installPhase = ''
                test -f ${tb}/terminal-browser/tool.toml
                test -x ${tb}/terminal-browser/bin/tb
                test -f ${tb}/terminal-browser/bin/cdp-download.mjs
                test -f ${tb}/terminal-browser/docs/procedure.md
                mkdir -p $out
                echo "terminal-browser tool layout OK: ${tb}"
              '';
            };
        }
      );
    };
}
