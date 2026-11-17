# =========================================================================
#  build.ps1 - build the OCaml chat server and client
#  Output:  bin\server.exe  bin\client.exe   (native)
#           bin\server.byte bin\client.byte  (bytecode, run with ocamlrun)
#  Intermediate files (.cmi/.cmx/.o ...) go to _build\ so src\ stays clean.
#  (Keep this file ASCII-only: Windows PowerShell 5.1 misreads UTF-8 without BOM.)
# =========================================================================
Set-Location $PSScriptRoot

# Re-read PATH so opam is found even if this shell was opened before opam was installed
$env:Path = [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')
# mingw gcc (used by ocamlopt to assemble/link) lives in opam's internal Cygwin
$env:Path = "$env:LOCALAPPDATA\opam\.cygwin\root\bin;$env:Path"

# Source lists - must be in dependency order (a module may only use the ones before it)
$SharedSources = @('src\shared\text.ml', 'src\shared\message.ml', 'src\shared\protocol.ml')
$ServerSources = @('src\shared\sync.ml') + $SharedSources + @(
    'src\data\repository.ml',      # Tier 3: Data
    'src\server\model.ml',         # Tier 2: MVC Model
    'src\server\chat_service.ml',  # Tier 2: MVC Controller
    'src\server\server.ml')        # Tier 2: entry point
$ClientSources = $SharedSources + @(
    'src\client\view.ml',          # Tier 1: MVC View
    'src\client\controller.ml',    # Tier 1: MVC Controller
    'src\client\client.ml')        # Tier 1: entry point

# Only libraries shipped with the compiler (no extra opam packages needed)
$NativeLibs   = @('-I', '+unix', '-I', '+threads', 'unix.cmxa', 'threads.cmxa')
$BytecodeLibs = @('-I', '+unix', '-I', '+threads', 'unix.cma',  'threads.cma')

# Build one program (native + bytecode)
function Build-Program([string]$Name, [string[]]$Sources) {
    $workDir = "_build\$Name"
    New-Item -ItemType Directory -Force $workDir, 'bin' | Out-Null   # work/output folders
    Copy-Item $Sources $workDir -Force                                # copy sources into work folder
    $files = $Sources | ForEach-Object { Split-Path $_ -Leaf }        # file names only, order kept
    Push-Location $workDir
    try {
        opam exec -- ocamlopt $NativeLibs $files -o "..\..\bin\$Name.exe"
        if (-not $?) { throw "native build failed: $Name" }
        opam exec -- ocamlc $BytecodeLibs $files -o "..\..\bin\$Name.byte"
        if (-not $?) { throw "bytecode build failed: $Name" }
    } finally {
        Pop-Location
    }
}

Build-Program 'server' $ServerSources
Build-Program 'client' $ClientSources
Write-Output "Build OK: bin\server.exe, bin\client.exe, bin\server.byte, bin\client.byte"
