# Start the chat server (bytecode, since antivirus blocks the native server.exe)
param([int]$Port = 9000)
Set-Location $PSScriptRoot
$env:Path = "$env:LOCALAPPDATA\opam\.cygwin\root\bin;" + [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')
opam exec -- ocamlrun server.byte $Port
