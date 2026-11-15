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
