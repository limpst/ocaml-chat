# Start a chat client. Open several terminals and run this in each one.
param([string]$HostName = "127.0.0.1", [int]$Port = 9000)
Set-Location $PSScriptRoot
.\client.exe $HostName $Port
