# OCaml chat build script (opam + ocamlopt, no extra packages needed)
Set-Location $PSScriptRoot
# pick up opam even if this shell was opened before opam was installed
$env:Path = [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')
# mingw gcc (used by ocamlopt to assemble/link) lives in opam's internal Cygwin
$env:Path = "$env:LOCALAPPDATA\opam\.cygwin\root\bin;$env:Path"
$libs = @('-I', '+unix', '-I', '+threads', 'unix.cmxa', 'threads.cmxa')

opam exec -- ocamlopt @libs model.ml protocol.ml repository.ml service.ml server.ml -o server.exe
if (-not $?) { exit 1 }
opam exec -- ocamlopt @libs model.ml protocol.ml view.ml controller.ml client.ml -o client.exe
if (-not $?) { exit 1 }
# bytecode builds (run with ocamlrun; used for the server because antivirus flags server.exe)
$blibs = @('-I', '+unix', '-I', '+threads', 'unix.cma', 'threads.cma')
opam exec -- ocamlc $blibs model.ml protocol.ml repository.ml service.ml server.ml -o server.byte
if (-not $?) { exit 1 }
opam exec -- ocamlc $blibs model.ml protocol.ml view.ml controller.ml client.ml -o client.byte
if (-not $?) { exit 1 }
Write-Output "Build OK: server.exe, client.exe, server.byte, client.byte"
