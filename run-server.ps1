# Start the chat server (default port 9000).
# Runs the bytecode build with ocamlrun because some antivirus tools flag the fresh server.exe.
param([int]$Port = 9000)
Set-Location $PSScriptRoot
$env:Path = "$env:LOCALAPPDATA\opam\.cygwin\root\bin;" + [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')
opam exec -- ocamlrun bin\server.byte $Port
