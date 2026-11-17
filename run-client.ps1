# Start a chat client. Run it in several terminals to chat between them.
param([string]$HostName = "127.0.0.1", [int]$Port = 9000)
Set-Location $PSScriptRoot
.\bin\client.exe $HostName $Port
