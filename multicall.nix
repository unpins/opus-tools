# opus-tools ships three command-line tools — `opusenc` (encode), `opusdec`
# (decode/play) and `opusinfo` (inspect Opus streams). To honour the unpins
# one-pkg-one-bin rule we post-link them into a single multicall binary at
# $out/bin/opusenc (a busybox-style dispatcher named after the flagship tool, as
# the unpins CI resolves result/bin/<binName>); `lib.withAliases` then embeds
# `opusdec` and `opusinfo` as UNPIN_META aliases so unpin's installer recreates
# the argv[0] shims.
#
# Why a post-link route (no source patch): the three tools are separate automake
# programs that share the heavy static archives — libopusenc / libopus / libFLAC
# / libogg and (for opusdec) opusfile+opusurl+openssl. opus-tools sets per-target
# CFLAGS (opusenc_CFLAGS, opusdec_CFLAGS, …), so automake compiles every shared
# source into a per-tool object (opusenc-opus_header.o vs opusdec-opus_header.o,
# …) — no object is shared between tools, and the same-named globals in those
# duplicate objects (opus_header_*, picture_*, plus the three `main`s) would
# collide on a naive merge. So we reuse the proven ld-free rename recipe (cf.
# flac/libwebp): per tool, build ONE redef map (main → <tool>_main, every other
# strong defined global foo → <tool>__foo) from the tool's raw objects and
# objcopy it onto each object in place — objcopy rewrites the definition AND every
# relocation, so each tool stays internally consistent and its symbols no longer
# clash with the other tools'. The renamed raw objects, not an `ld -r` partial,
# go into the final link: ld64's `-r` would demote a `main` that owns
# function-local statics from global (T) to local (t), emptying the map and
# leaving <tool>_main undefined on darwin. The shared archives are linked ONCE at
# the end, so the binary carries one copy of each codec lib, not three.
#
# Unlike the CMake suites, opus-tools is autotools and has no link.txt; instead
# we capture each tool's real link command (the autotools analog) by removing the
# linked binaries and relinking with `make V=1`, then parse that command for the
# tool's objects and its -l/-L/archive tokens. The exact link list the build
# actually configured is therefore reused verbatim on every platform (musl ELF /
# Mach-O / mingw) — no hard-coded dependency set to drift.
#
# Shared by the native `build` (pkgsStatic) and the `windowsBuild`
# (mingwStaticCross) paths; isDarwin/isWindows come from the INPUT derivation's
# stdenv (under windowsBuild `pkgs` is the x86_64-linux root — the cross lives
# inside mingwStaticCross — so `pkgs.stdenv` would wrongly say "not Windows").
{ lib }:
{ pkgs, opusTools }:
let
  isDarwin = opusTools.stdenv.hostPlatform.isDarwin or false;
  isWindows = opusTools.stdenv.hostPlatform.isWindows or false;

  multicall = opusTools.overrideAttrs (old: {
    pname = "opus-tools-multi";
    outputs = [ "out" ];

    # Upstream sets meta.platforms = unix, which excludes the mingw (windows)
    # host and makes nix refuse to evaluate the cross build. opus-tools is
    # portable C and cross-compiles cleanly, so lift the restriction.
    meta = (old.meta or { }) // {
      platforms = lib.platforms.all;
      broken = false;
    };

    # Two buildInputs fix-ups, both about meta.platforms on the mingw cross:
    #   * Drop libao — nixpkgs still lists it, but opus-tools 0.2 dropped libao
    #     (no AO reference left in Makefile.am/configure.ac; opusdec plays via
    #     sndio/OSS), so it never links, and libao is meta.platforms = unix.
    #   * Lift the meta.platforms = unix guard on the xiph codec libs
    #     (libopusenc, opusfile). They are portable C and cross-compile to mingw
    #     cleanly; the restriction is just over-conservative upstream metadata.
    #     Overriding meta does not change the store path, only the eval guard.
    buildInputs =
      let
        metaAllow = d: d.overrideAttrs (o: {
          meta = (o.meta or { }) // { platforms = lib.platforms.all; broken = false; };
        });
        xiph = [ "libopusenc" "opusfile" ];
      in
      builtins.map (d: if builtins.elem (d.pname or "") xiph then metaAllow d else d)
        (builtins.filter (d: (d.pname or "") != "libao") (old.buildInputs or [ ]));

    # opus-tools' configure detects pkg-config with AC_CHECK_PROG(pkg-config),
    # which looks for the *unprefixed* name. Under a static/cross stdenv the
    # wrapper is host-prefixed (x86_64-…-musl-pkg-config), so the check fails,
    # HAVE_PKG_CONFIG=no, and the FLAC probe falls back to a bare `-lFLAC` link
    # test that can't resolve libogg under static → "FLAC 1.1.3 required". Force
    # the flag so every PKG_CHECK_MODULES (ogg/opus/opusfile/opusenc/flac) takes
    # the proper pkg-config path. AC_CHECK_PROG is a no-op when the var is preset,
    # and the native dynamic build already had it yes, so this is safe everywhere.
    preConfigure = (old.preConfigure or "") + ''
      export HAVE_PKG_CONFIG=yes
    '';

    # We re-link the tools ourselves and smoke-test the result; the upstream
    # version check runs a single tool we'd be replacing, so skip it.
    doCheck = false;
    doInstallCheck = false;

    postBuild = (old.postBuild or "") + ''
      set -e
      mkdir -p mc
      TOOLS="opusenc opusdec opusinfo"

      # Capture each tool's real link command (autotools' analog of CMake's
      # link.txt). The three programs are plain (non-libtool) automake targets,
      # so each links with a single `$(CC) … -o <tool> <objs> <libs>` line.
      # Remove the binaries and relink verbosely to print those lines. We invoke
      # `make` with no explicit targets: naming `opusenc` works on ELF/Mach-O but
      # not on mingw, where the real target carries $(EXEEXT) (`opusenc.exe`) and
      # `make opusenc` errors with "No rule to make target". A bare `make` just
      # relinks the binaries we removed (objects are already up to date).
      for t in $TOOLS; do rm -f "$t" "$t.exe"; done
      make V=1 > mc/linklog 2>&1 || { cat mc/linklog; exit 1; }

      # Pull each tool's link line: it names the target with `-o <tool>` and,
      # unlike the compile lines, has no `-c`. Take the last such line per tool.
      getline() { awk -v t="$1" '
        $0 ~ ("-o (\\./)?" t "(\\.exe)?( |$)") && $0 !~ / -c / { last=$0 } END{ print last }
      ' mc/linklog; }

      # From a link line, the objects are the *.o / *.obj tokens; the libraries
      # are the -l / -L / *.a / -pthread tokens, harvested into the shared link
      # list (dedup first-seen, dependency-correct order). We deliberately drop
      # the configure-added hardening LDFLAGS (-pie, -Wl,-z,relro, -Wl,-z,now):
      # they are irrelevant to the merged binary and -pie clashes with the
      # `-static` runtime fold on the mingw link.
      LIBS=""
      addlib() { case " $LIBS " in *" $1 "*) ;; *) LIBS="$LIBS $1" ;; esac; }
      classify() {
        case "$1" in
          *.dll.a)            ;;
          -l* | -L* | -pthread) addlib "$1" ;;
          /*.a)               addlib "$1" ;;
          *.a)                addlib "$(realpath -m "$1")" ;;
        esac
      }

      declare -A TOBJ
      for t in $TOOLS; do
        line=$(getline "$t")
        [ -n "$line" ] || { echo "no link line for $t"; exit 1; }
        objs=""
        for tok in $line; do
          case "$tok" in
            *.o | *.obj) objs="$objs $tok" ;;
            *)           classify "$tok" ;;
          esac
        done
        TOBJ[$t]="$objs"
      done

      # Mach-O leads C symbols with '_'; detect once from opusenc's objects.
      if $NM --defined-only ''${TOBJ[opusenc]} 2>/dev/null | awk '$3=="_main"{f=1} END{exit !f}'; then
        up=_
      else
        up=""
      fi

      # Per tool: one redef map (main → <t>_main, other strong defined globals
      # foo → <t>__foo; skip weak/COMDAT W/V and names containing '.'), applied to
      # each of that tool's raw objects so refs follow the rename and the tools'
      # duplicated globals never collide.
      MCOBJS=""
      for t in $TOOLS; do
        $NM --defined-only ''${TOBJ[$t]} 2>/dev/null \
          | awk -v t="$t" -v up="$up" '
              $2 ~ /^[A-TX-Z]$/ && $2 != "W" && $2 != "V" {
                sym = $3; core = sym
                if (up != "" && index(core, up) == 1) core = substr(core, 2)
                if (index(core, ".") != 0) next
                if (core !~ /^[A-Za-z_][A-Za-z0-9_]*$/) next
                if (core == "main") print sym " " up t "_main"
                else                print sym " " up t "__" core
              }' | sort -u > "mc/$t.redef"
        for o in ''${TOBJ[$t]}; do
          d="mc/$t.$(basename "$o")"
          cp "$o" "$d"
          [ -s "mc/$t.redef" ] && $OBJCOPY --redefine-syms="mc/$t.redef" "$d"
          MCOBJS="$MCOBJS $d"
        done
      done

      # Dispatcher: basename(argv[0]) → <tool>_main. The canonical name (opusenc)
      # and any unknown argv[0] fall through to a `<bin> <applet> …` form and
      # finally to opusenc_main, so the bare dispatcher stays callable (its
      # `--version` smoke reaches opusenc_main) and survives a rename (CI smoke
      # copies it to smoke.exe).
      {
        echo '#include <string.h>'
        for t in $TOOLS; do echo "int ''${t}_main(int, char **);"; done
        echo 'struct ap { const char *n; int (*f)(int, char **); };'
        echo 'static const struct ap aps[] = {'
        for t in $TOOLS; do echo "    {\"$t\", ''${t}_main},"; done
        cat <<'CBODY'
    {0, 0}
};
static void base_of(char *d, size_t cap, const char *s) {
    const char *p = s, *x;
    x = strrchr(p, '/'); if (x) p = x + 1;
#ifdef _WIN32
    x = strrchr(p, '\\'); if (x) p = x + 1;
#endif
    size_t n = strlen(p); if (n >= cap) n = cap - 1;
    memcpy(d, p, n); d[n] = 0;
    if (n > 4 && strcmp(d + n - 4, ".exe") == 0) d[n - 4] = 0;
}
int main(int argc, char **argv) {
    char b[64];
    const char *a0 = (argc > 0 && argv[0]) ? argv[0] : "opusenc";
    base_of(b, sizeof b, a0);
    for (const struct ap *a = aps; a->n; a++)
        if (strcmp(b, a->n) == 0) return a->f(argc, argv);
    /* canonical/unknown argv[0]: allow `opusenc <applet> [args]`, else opusenc. */
    if (argc >= 2) {
        char c[64]; base_of(c, sizeof c, argv[1]);
        for (const struct ap *a = aps; a->n; a++)
            if (strcmp(c, a->n) == 0) return a->f(argc - 1, argv + 1);
    }
    return opusenc_main(argc, argv);
}
CBODY
      } > mc/dispatcher.c
      $CC -O2 -c -o mc/dispatcher.o mc/dispatcher.c

      # Final link: shared archives, once. On GNU-ld targets wrap them in a group
      # to absorb back-references; ld64 (darwin) rejects --start-group but
      # re-scans archives on its own, so list them plain there.
      if ${if isDarwin then "true" else "false"}; then
        GO=""; GC=""
      else
        GO="-Wl,--start-group"; GC="-Wl,--end-group"
      fi
      # mingw: this manual link bypasses the `-static` the normal
      # mingwStaticCross build applies. Link the runtime fully static so every -l
      # resolves to its .a and only real Windows system DLLs remain next to the
      # .exe (no libgcc_s / libstdc++ / mcfgthread companions).
      MCF=""
      ${lib.optionalString isWindows ''MCF="-static"''}
      $CC -O2 \
        $MCOBJS mc/dispatcher.o \
        $GO $LIBS $GC -lm $MCF \
        -o mc/opusenc
      [ -f mc/opusenc ] || mv mc/opusenc.exe mc/opusenc
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/share/man/man1"
      # Canonical binary is named after the flagship tool (opusenc) — a
      # busybox-style dispatcher; opusdec/opusinfo are symlinks that
      # lib.withAliases turns into argv[0] aliases.
      install -m755 mc/opusenc "$out/bin/opusenc"
      ln -s opusenc "$out/bin/opusdec"
      ln -s opusenc "$out/bin/opusinfo"

      # Man pages ship as source (man/<tool>.1); install all three so the set
      # matches nixpkgs' opus-tools man output (no winManRoot needed).
      mandir=""
      for d in ../man man "$src/man"; do [ -f "$d/opusenc.1" ] && mandir="$d" && break; done
      if [ -n "$mandir" ]; then
        for m in opusenc opusdec opusinfo; do
          [ -f "$mandir/$m.1" ] && cp "$mandir/$m.1" "$out/share/man/man1/$m.1"
        done
      fi
      runHook postInstall
    '';
  });

  aliased = lib.withAliases pkgs
    {
      primary = "opusenc";
      aliasesFromSymlinksIn = "bin";
    }
    multicall;
in
if isWindows
then aliased.overrideAttrs (o: {
  postFixup = (o.postFixup or "") + ''
    [ -f "$out/bin/opusenc" ] && mv "$out/bin/opusenc" "$out/bin/opusenc.exe"
  '';
})
else aliased
