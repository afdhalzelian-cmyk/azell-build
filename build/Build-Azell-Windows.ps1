param(
    [Parameter(Mandatory = $true)]
    [string] $SourceDirectory
)

$ErrorActionPreference = 'Stop'
$upstream = '25d57d98736634b223cf03dd44053fa3abb73eac'
$target = & node -p "process.platform + '-' + process.arch"
if ($LASTEXITCODE -ne 0 -or $target -ne 'win32-x64') {
    throw 'Run this build with x64 Node.js on an x64 Windows build host.'
}

function Invoke-Pnpm {
    & pnpm.cmd @args
    if ($LASTEXITCODE -ne 0) {
        throw "pnpm failed: $args (exit $LASTEXITCODE)"
    }
}

Push-Location -LiteralPath $SourceDirectory
try {
    & git merge-base --is-ancestor $upstream HEAD
    if ($LASTEXITCODE -ne 0) {
        throw "The Azell build expects Cherry Studio v2.2.2 at $upstream or a branch based on it."
    }
    if (-not (Test-Path -LiteralPath 'electron-builder.azell.config.cjs' -PathType Leaf)) {
        throw 'Apply the Azell integration patch before building.'
    }

    Invoke-Pnpm install --frozen-lockfile
    Invoke-Pnpm run build:release
    & node scripts/release/js-bundle.js verify global
    if ($LASTEXITCODE -ne 0) {
        throw 'The compiled JavaScript bundle failed verification.'
    }
    Invoke-Pnpm run build

    # Cherry Studio's download-binaries.js invokes the Windows command
    # `powershell ... Expand-Archive` while electron-builder is packaging.
    # GitHub Actions runs this script under PowerShell 7. Its PSModulePath can
    # leak the PowerShell 7 Archive module into the child Windows PowerShell
    # process, causing an ExtractToDirectory overload error. Force child
    # `powershell` calls to use the inbox Windows PowerShell 5.1 modules.
    $windowsPowerShellDirectory = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0'
    $windowsPowerShellExe = Join-Path $windowsPowerShellDirectory 'powershell.exe'
    $windowsPowerShellModuleDirectory = Join-Path $windowsPowerShellDirectory 'Modules'

    if (-not (Test-Path -LiteralPath $windowsPowerShellExe -PathType Leaf)) {
        throw "Windows PowerShell 5.1 was not found: $windowsPowerShellExe"
    }
    if (-not (Test-Path -LiteralPath $windowsPowerShellModuleDirectory -PathType Container)) {
        throw "Windows PowerShell 5.1 module directory was not found: $windowsPowerShellModuleDirectory"
    }

    $modulePaths = @(
        $windowsPowerShellModuleDirectory
        (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }

    # Put powershell.exe 5.1 first for child processes launched by Node.
    $env:PATH = "$windowsPowerShellDirectory$([System.IO.Path]::PathSeparator)$env:PATH"

    # Do not expose PowerShell 7 module folders to the child Windows PowerShell.
    $env:PSModulePath = $modulePaths -join [System.IO.Path]::PathSeparator

    $resolvedPowerShell = (Get-Command powershell -CommandType Application -ErrorAction Stop).Source
    if ([System.IO.Path]::GetFullPath($resolvedPowerShell) -ne [System.IO.Path]::GetFullPath($windowsPowerShellExe)) {
        throw "The child 'powershell' command does not resolve to Windows PowerShell 5.1: $resolvedPowerShell"
    }

    $archiveProbe = & $windowsPowerShellExe -NoLogo -NoProfile -NonInteractive -Command 'Import-Module Microsoft.PowerShell.Archive -ErrorAction Stop; "{0}|{1}" -f $PSVersionTable.PSVersion, (Get-Module Microsoft.PowerShell.Archive).Path'
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to load Microsoft.PowerShell.Archive under Windows PowerShell 5.1.'
    }

    $archiveProbeText = ($archiveProbe -join '').Trim()
    $archiveProbeParts = $archiveProbeText -split '\|', 2
    if ($archiveProbeParts.Count -ne 2 -or $archiveProbeParts[0] -notmatch '^5\.1') {
        throw "Unexpected ZIP extraction PowerShell/module result: $archiveProbeText"
    }

    $expectedArchiveModuleRoot = Join-Path $windowsPowerShellModuleDirectory 'Microsoft.PowerShell.Archive'
    if (-not $archiveProbeParts[1].StartsWith($expectedArchiveModuleRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The ZIP extraction module is not the Windows PowerShell 5.1 module: $($archiveProbeParts[1])"
    }

    Write-Host "ZIP extraction shell: $windowsPowerShellExe"
    Write-Host "ZIP extraction module: $($archiveProbeParts[1])"

    Invoke-Pnpm exec electron-builder --config electron-builder.azell.config.cjs --win --x64 --publish never

    $version = & node -p "require('./package.json').version"
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to determine the package version.'
    }
    @(
        "dist-azell/Azell-${version}-x64-setup.exe"
        "dist-azell/Azell-${version}-x64-portable.exe"
    ) | ForEach-Object {
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
            throw "Expected build output is missing: $_"
        }
        Get-FileHash -LiteralPath $_ -Algorithm SHA256
    }
}
finally {
    Pop-Location
}
