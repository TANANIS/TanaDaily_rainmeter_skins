param(
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$sourceSkin = Join-Path $repo 'src\Skins\MistRainWorkbench'
$manifest = Join-Path $repo 'RMSKIN.ini'
$dist = Join-Path $repo 'dist'
$stage = Join-Path ([IO.Path]::GetTempPath()) ('TanaDaily-rmskin-' + [Guid]::NewGuid().ToString('N'))
$archive = Join-Path $dist ('TanaDaily-MistRainWorkbench-' + $Version + '.rmskin')

try {
    [IO.Directory]::CreateDirectory((Join-Path $stage 'Skins')) | Out-Null
    [IO.Directory]::CreateDirectory($dist) | Out-Null
    Copy-Item -LiteralPath $manifest -Destination (Join-Path $stage 'RMSKIN.ini')
    Copy-Item -LiteralPath $sourceSkin -Destination (Join-Path $stage 'Skins') -Recurse

    $temporaryZip = Join-Path ([IO.Path]::GetTempPath()) ('TanaDaily-' + [Guid]::NewGuid().ToString('N') + '.zip')
    try {
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $temporaryZip -CompressionLevel Optimal
        # Rainmeter's current package format is a ZIP followed by a 16-byte
        # footer: little-endian Int64 ZIP size, one flags byte, and "RMSKIN\0".
        # Without it SkinInstaller treats the archive as legacy Rainstaller.
        $stream = [IO.File]::Open($temporaryZip, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            $zipLength = $stream.Length
            $stream.Position = $zipLength
            $writer = [IO.BinaryWriter]::new($stream, [Text.Encoding]::ASCII, $true)
            try {
                $writer.Write([Int64]$zipLength)
                $writer.Write([Byte]0)
                $writer.Write([Text.Encoding]::ASCII.GetBytes("RMSKIN`0"))
                $writer.Flush()
            }
            finally { $writer.Dispose() }
        }
        finally { $stream.Dispose() }
        Copy-Item -LiteralPath $temporaryZip -Destination $archive -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryZip) { Remove-Item -LiteralPath $temporaryZip -Force }
    }

    Get-Item -LiteralPath $archive | Select-Object FullName, Length
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
