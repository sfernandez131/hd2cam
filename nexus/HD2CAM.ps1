# HD2CAM installer, launcher and uninstaller for HELLDIVERS (2015).
#
# Source and latest version: https://github.com/sfernandez131/hd2cam
# Save it next to hd2cam.ljbc, open PowerShell in that folder and enter:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\HD2CAM.ps1
# then choose Install or Uninstall. (Windows' own "Run with PowerShell"
# refuses downloaded scripts on a default setup.)
#
# The download contains only the mod (hd2cam.ljbc). This script patches it
# into your own copy of the game: it finds the game's loader script inside
# one game file (contents\9cf71054ea26dddf), swaps in the mod, and keeps the
# original file so Uninstall can put it back.
#
#   -Action Install    patch the game, copy the kit to <game>\HD2CAM, make the
#                      "Helldivers (HD2CAM)" desktop shortcut
#   -Action Launch     re-apply the mod if Steam restored the game file, then
#                      start the game through Steam (what the shortcut runs)
#   -Action Uninstall  restore the original file, remove the shortcut and
#                      the <game>\HD2CAM folder
#   -Action Status     report whether the mod is installed
param(
    [ValidateSet('', 'Install', 'Launch', 'Uninstall', 'Status')]
    [string]$Action = ''
)
$ErrorActionPreference = 'Stop'

$AppId         = 394510
$DefaultBundle = '9cf71054ea26dddf'
# MurmurHash64A of "lua" and "foundation/lua/build_date_information".
$LuaType       = [UInt64]::Parse('a14e8dfa2cd117e2', 'HexNumber')
$LoaderName    = [UInt64]::Parse('35546153a5bb59d2', 'HexNumber')
$BundleVersion = [UInt32]::Parse('F0000004', 'HexNumber')
$ChunkSize     = 0x10000
$ShortcutName  = 'Helldivers (HD2CAM).lnk'
$KitFiles      = @('hd2cam.ljbc', 'HD2CAM.ps1', 'README.txt')
$Here          = Split-Path -Parent $MyInvocation.MyCommand.Path


# ---------------------------------------------------------------- game files

function Find-Game {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    $libraries = @()
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $libraries += $steam
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libraries += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    foreach ($lib in ($libraries | Select-Object -Unique)) {
        $game = Join-Path $lib 'steamapps\common\Helldivers'
        if ((Test-Path (Join-Path $lib "steamapps\appmanifest_$AppId.acf")) -and (Test-Path $game)) {
            return $game
        }
    }
    throw 'Could not find HELLDIVERS in any Steam library. Is it installed through Steam?'
}

# A bundle is a header (version, payload size, 0) and 64 KB chunks, each
# zlib-compressed, or stored as-is when its size field is exactly 64 KB.
function Read-Payload([string]$Path) {
    $data = [IO.File]::ReadAllBytes($Path)
    if ([BitConverter]::ToUInt32($data, 0) -ne $BundleVersion) { throw "$Path is not a HELLDIVERS bundle." }
    $total = [BitConverter]::ToUInt32($data, 4)
    $out = New-Object IO.MemoryStream
    $pos = 12
    while ($pos -lt $data.Length -and $out.Length -lt $total) {
        $size = [BitConverter]::ToInt32($data, $pos)
        $pos += 4
        if ($size -eq $ChunkSize) {
            $out.Write($data, $pos, $size)
        } else {
            # zlib = 2-byte header + raw deflate + checksum
            $in = New-Object IO.MemoryStream($data, ($pos + 2), ($size - 2))
            $inflate = New-Object IO.Compression.DeflateStream($in, [IO.Compression.CompressionMode]::Decompress)
            $inflate.CopyTo($out)
            $inflate.Dispose()
        }
        $pos += $size
    }
    if ($out.Length -lt $total) { throw "$Path is truncated." }
    $out.SetLength($total)   # the last chunk is zero-padded
    return , $out.ToArray()
}

# Written back with every chunk stored as-is (no compression). The game's
# own files use stored chunks too; the file is just larger (about 2 MB).
function Write-Bundle([byte[]]$Payload, [string]$Path) {
    $out = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter($out)
    $w.Write([UInt32]$BundleVersion); $w.Write([UInt32]$Payload.Length); $w.Write([UInt32]0)
    for ($i = 0; $i -lt $Payload.Length; $i += $ChunkSize) {
        $block = New-Object byte[] $ChunkSize   # the last block is zero-padded
        [Array]::Copy($Payload, $i, $block, 0, [Math]::Min($ChunkSize, $Payload.Length - $i))
        $w.Write([UInt32]$ChunkSize); $w.Write($block)
    }
    $w.Flush()
    # Write next to it, then swap in, so a failure never leaves half a file.
    $tmp = "$Path.hd2cam-tmp"
    [IO.File]::WriteAllBytes($tmp, $out.ToArray())
    Move-Item $tmp $Path -Force
}

# Where the loader script sits in a payload: entries follow a 4-byte count,
# 256 bytes of properties and a (type, name) index; each entry is type,
# name, variant count, unknown, then (language, size, stream size) per
# variant, then the variants' data.
function Find-Loader([byte[]]$Payload) {
    $count = [BitConverter]::ToUInt32($Payload, 0)
    $pos = 260 + $count * 16
    for ($e = 0; $e -lt $count; $e++) {
        $type = [BitConverter]::ToUInt64($Payload, $pos)
        $name = [BitConverter]::ToUInt64($Payload, $pos + 8)
        $nvar = [BitConverter]::ToUInt32($Payload, $pos + 16)
        $heads = $pos + 24
        $data = $heads + 12 * $nvar
        if ($type -eq $LuaType -and $name -eq $LoaderName) {
            return @{ SizePos = $heads + 4; DataPos = $data; DataLen = [BitConverter]::ToUInt32($Payload, $heads + 4) }
        }
        for ($v = 0; $v -lt $nvar; $v++) { $data += [BitConverter]::ToUInt32($Payload, $heads + 12 * $v + 4) }
        $pos = $data
    }
    return $null
}

function Get-LoaderBytes([byte[]]$Payload, $Loader) {
    $b = New-Object byte[] $Loader.DataLen
    [Array]::Copy($Payload, $Loader.DataPos, $b, 0, $Loader.DataLen)
    return , $b
}

function Test-Modded([byte[]]$Bytes) {
    return [Text.Encoding]::GetEncoding(28591).GetString($Bytes).Contains('HD2CAM')
}

function Set-Loader([byte[]]$Payload, $Loader, [byte[]]$New) {
    $out = New-Object IO.MemoryStream
    $out.Write($Payload, 0, $Loader.SizePos)
    $out.Write([BitConverter]::GetBytes([UInt32]$New.Length), 0, 4)
    $after = $Loader.SizePos + 4
    $out.Write($Payload, $after, $Loader.DataPos - $after)
    $out.Write($New, 0, $New.Length)
    $rest = $Loader.DataPos + $Loader.DataLen
    $out.Write($Payload, $rest, $Payload.Length - $rest)
    return , $out.ToArray()
}

function Get-Sha([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path))) -replace '-' }
    finally { $sha.Dispose() }
}

# ---------------------------------------------------------------- the mod

function Get-ModBytes([string]$Kit) {
    $code = [IO.File]::ReadAllBytes((Join-Path $Kit 'hd2cam.ljbc'))
    $out = New-Object IO.MemoryStream
    $out.Write([BitConverter]::GetBytes([UInt32]$code.Length), 0, 4)
    $out.Write([BitConverter]::GetBytes([UInt32]2), 0, 4)
    $out.Write($code, 0, $code.Length)
    return , $out.ToArray()
}

function Get-Paths {
    $game = Find-Game
    $home_ = Join-Path $game 'HD2CAM'
    return @{
        Game   = $game
        Home   = $home_
        Bundle = Join-Path $game "contents\$DefaultBundle"
        Backup = Join-Path $home_ "backup\$DefaultBundle"
        # Backups made by earlier HD2CAM versions.
        Legacy = Join-Path $game "hd2cam_backup\$DefaultBundle"
        Stamp  = Join-Path $home_ 'installed.sha256'
    }
}

function Assert-GameClosed {
    if (Get-Process -Name 'helldivers' -ErrorAction SilentlyContinue) {
        throw 'HELLDIVERS is running. Close the game, then try again.'
    }
}

# The original game file: the live one if it isn't modded, else a backup.
function Get-Original($P) {
    $payload = Read-Payload $P.Bundle
    $loader = Find-Loader $payload
    if (-not $loader) { throw 'Could not find the game''s loader script. This game version is not supported.' }
    if (-not (Test-Modded (Get-LoaderBytes $payload $loader))) {
        return @{ Payload = $payload; Loader = $loader; Live = $true }
    }
    foreach ($b in $P.Backup, $P.Legacy) {
        if (Test-Path $b) {
            $payload = Read-Payload $b
            $loader = Find-Loader $payload
            if ($loader -and -not (Test-Modded (Get-LoaderBytes $payload $loader))) {
                return @{ Payload = $payload; Loader = $loader; Live = $false; Path = $b }
            }
        }
    }
    throw 'The game file is already modified and no original backup was found. In Steam: right-click HELLDIVERS > Properties > Installed Files > Verify integrity of game files, then install again.'
}

# Patch the game. Returns 'installed', 'updated', 'reapplied' or 'current'.
function Invoke-Patch($P, [string]$Kit) {
    $mod = Get-ModBytes $Kit
    # Quick path for the launcher: the file is exactly what we last wrote.
    if ((Test-Path $P.Stamp) -and (Test-Path $P.Bundle) -and
        (Get-Content $P.Stamp -Raw).Trim() -eq (Get-Sha $P.Bundle)) {
        $payload = Read-Payload $P.Bundle
        $loader = Find-Loader $payload
        if ($loader -and [Convert]::ToBase64String((Get-LoaderBytes $payload $loader)) -eq [Convert]::ToBase64String($mod)) {
            return 'current'
        }
    }
    Assert-GameClosed
    $orig = Get-Original $P
    $result = 'updated'
    if ($orig.Live) {
        # Unmodified game file (first install, or Steam restored it after an
        # update or "Verify integrity"): it becomes the backup.
        New-Item -ItemType Directory -Force (Split-Path $P.Backup) | Out-Null
        Copy-Item $P.Bundle $P.Backup -Force
        $result = if ((Test-Path $P.Stamp) -or (Test-Path $P.Legacy)) { 'reapplied' } else { 'installed' }
    }
    $patched = Set-Loader $orig.Payload $orig.Loader $mod
    Write-Bundle $patched $P.Bundle
    New-Item -ItemType Directory -Force $P.Home | Out-Null
    Set-Content $P.Stamp (Get-Sha $P.Bundle)
    return $result
}

function New-Shortcut($P) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut((Join-Path $desktop $ShortcutName))
    $lnk.TargetPath = Join-Path $PSHOME 'powershell.exe'
    $script = Join-Path $P.Home 'HD2CAM.ps1'
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Action Launch"
    $lnk.WorkingDirectory = $P.Home
    $lnk.WindowStyle = 7   # minimized
    $exe = Join-Path $P.Game 'binaries\helldivers.exe'
    if (Test-Path $exe) { $lnk.IconLocation = "$exe,0" }
    $lnk.Description = 'Re-applies HD2CAM if Steam restored the game files, then starts HELLDIVERS'
    $lnk.Save()
}

# ---------------------------------------------------------------- actions

function Install {
    $P = Get-Paths
    Write-Host "HELLDIVERS found at: $($P.Game)"
    $result = Invoke-Patch $P $Here
    # Keep a copy of the kit in the game folder for the launcher/uninstaller.
    New-Item -ItemType Directory -Force $P.Home | Out-Null
    if ((Resolve-Path $Here).Path -ne (Resolve-Path $P.Home).Path) {
        foreach ($f in $KitFiles) { Copy-Item (Join-Path $Here $f) (Join-Path $P.Home $f) -Force }
    }
    New-Shortcut $P
    switch ($result) {
        'current' { Write-Host 'HD2CAM is already installed and up to date.' }
        default   { Write-Host "HD2CAM $result." }
    }
    Write-Host ''
    Write-Host "Start the game with the '$($ShortcutName -replace '\.lnk$')' shortcut on your desktop."
    Write-Host 'It puts the mod back automatically if Steam ever restores the game files.'
}

function Launch {
    try {
        $P = Get-Paths
        $result = Invoke-Patch $P $Here
        if ($result -ne 'current') { Write-Host "HD2CAM $result." }
    } catch {
        Write-Warning "HD2CAM could not be applied: $($_.Exception.Message)"
        Write-Warning 'Starting the game without it in 10 seconds...'
        Start-Sleep -Seconds 10
    }
    Start-Process "steam://rungameid/$AppId"
}

function Uninstall {
    $P = Get-Paths
    Write-Host "HELLDIVERS found at: $($P.Game)"
    Assert-GameClosed
    $payload = Read-Payload $P.Bundle
    $loader = Find-Loader $payload
    if ($loader -and (Test-Modded (Get-LoaderBytes $payload $loader))) {
        $orig = Get-Original $P
        Copy-Item $orig.Path $P.Bundle -Force
        Write-Host 'Original game file restored.'
    } else {
        Write-Host 'The game file is already the original.'
    }
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) $ShortcutName
    if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host 'Desktop shortcut removed.' }
    if (Test-Path $P.Home) {
        if ((Resolve-Path $Here).Path -eq (Resolve-Path $P.Home).Path) {
            # Running from inside that folder: clear it except the scripts
            # running right now, which the player deletes afterwards.
            Get-ChildItem $P.Home | Where-Object { $_.Name -ne 'HD2CAM.ps1' } | Remove-Item -Recurse -Force
            Write-Host "You can now delete the folder $($P.Home)."
        } else {
            Remove-Item $P.Home -Recurse -Force
            Write-Host "Removed $($P.Home)."
        }
    }
    Write-Host 'HD2CAM uninstalled.'
}

function Status {
    $P = Get-Paths
    $payload = Read-Payload $P.Bundle
    $loader = Find-Loader $payload
    $bytes = Get-LoaderBytes $payload $loader
    if (-not (Test-Modded $bytes)) { Write-Host 'Not installed (original game file).'; return }
    $same = [Convert]::ToBase64String($bytes) -eq [Convert]::ToBase64String((Get-ModBytes $Here))
    Write-Host ('Installed' + $(if ($same) { ' (this version).' } else { ' (a different version or build).' }))
}

# No -Action (Run with PowerShell): ask, and keep the window open at the end.
$interactive = -not $Action
if ($interactive) {
    Write-Host 'HD2CAM for HELLDIVERS'
    Write-Host ''
    Write-Host '  1  Install or update'
    Write-Host '  2  Uninstall'
    Write-Host '  3  Status'
    Write-Host ''
    $choice = Read-Host 'Choose 1, 2 or 3'
    $Action = @{ '1' = 'Install'; '2' = 'Uninstall'; '3' = 'Status' }[$choice.Trim()]
    if (-not $Action) { Write-Host 'Nothing chosen.'; Read-Host 'Press Enter to close' | Out-Null; exit 0 }
    Write-Host ''
}
$code = 0
try {
    & $Action
} catch {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $code = 1
}
if ($interactive) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null }
exit $code
