#!/usr/bin/env sh
# =========================================================================
#  build.sh - build the OCaml chat server and client (Linux / macOS)
#  Same output as build.ps1:
#    bin/server.exe  bin/client.exe   (native)
#    bin/server.byte bin/client.byte  (bytecode, run with ocamlrun)
#  Intermediate files go to _build/ so src/ stays clean.
#  Uses `opam exec --` when opam is available, plain compilers otherwise.
# =========================================================================
set -eu
cd "$(dirname "$0")"

if command -v opam >/dev/null 2>&1; then RUN="opam exec --"; else RUN=""; fi

# Source lists - must be in dependency order (a module may only use the ones before it)
SHARED="src/shared/text.ml src/shared/message.ml src/shared/protocol.ml"
SERVER="src/shared/sync.ml $SHARED src/data/repository.ml src/server/model.ml src/server/chat_service.ml src/server/server.ml"
CLIENT="$SHARED src/client/view.ml src/client/controller.ml src/client/client.ml"

# Build one program (native + bytecode)
build_program() {
    name=$1; shift
    work="_build/$name"
    mkdir -p "$work" bin
    cp "$@" "$work/"
    files=""
    for src in "$@"; do files="$files $(basename "$src")"; done
    (
        cd "$work"
        # shellcheck disable=SC2086
        $RUN ocamlopt -I +unix -I +threads unix.cmxa threads.cmxa $files -o "../../bin/$name.exe"
        # shellcheck disable=SC2086
        $RUN ocamlc -I +unix -I +threads unix.cma threads.cma $files -o "../../bin/$name.byte"
    )
}

# shellcheck disable=SC2086
build_program server $SERVER
# shellcheck disable=SC2086
build_program client $CLIENT
echo "Build OK: bin/server.exe, bin/client.exe, bin/server.byte, bin/client.byte"
