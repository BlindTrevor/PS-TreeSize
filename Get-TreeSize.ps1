<#
.SYNOPSIS
    Scans directories and displays a tree view of folder and file sizes, similar to TreeSize Free.

.DESCRIPTION
    Get-TreeSize recursively scans a specified directory (or the system drive by default) and
    displays a hierarchical tree view of all folders and their sizes, sorted by size descending.

.PARAMETER Path
    The root directory to scan. Defaults to the system drive (e.g., C:\).

.PARAMETER Depth
    Maximum depth of the directory tree to display. Defaults to unlimited (-1).

.PARAMETER MinSize
    Minimum size in bytes to display an entry. Defaults to 0.

.EXAMPLE
    .\Get-TreeSize.ps1
    Scans the system drive using default settings.

.EXAMPLE
    .\Get-TreeSize.ps1 -Path "C:\Users"
    Scans the C:\Users directory.

.EXAMPLE
    .\Get-TreeSize.ps1 -Path "D:\" -Depth 3
    Scans D:\ up to 3 levels deep.

.EXAMPLE
    .\Get-TreeSize.ps1 -Path "C:\Windows" -MinSize 1MB
    Scans C:\Windows and only shows entries larger than 1 MB.
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string]$Path = "$($env:SystemDrive)\",

    [Parameter()]
    [int]$Depth = -1,

    [Parameter()]
    [long]$MinSize = 0
)

function Format-Size {
    param ([long]$Bytes)

    switch ($Bytes) {
        { $_ -ge 1TB } { return "{0,8:N2} TB" -f ($_ / 1TB) }
        { $_ -ge 1GB } { return "{0,8:N2} GB" -f ($_ / 1GB) }
        { $_ -ge 1MB } { return "{0,8:N2} MB" -f ($_ / 1MB) }
        { $_ -ge 1KB } { return "{0,8:N2} KB" -f ($_ / 1KB) }
        default        { return "{0,8:N2}  B" -f $_ }
    }
}

# Script-scope state used to track scan progress across recursive calls
$script:scanStartTime      = $null
$script:topLevelTotal      = 0
$script:topLevelDone       = 0
$script:progressPct        = 0
$script:progressEta        = -1
$script:progressActivity   = ""
$script:lastProgressUpdate = [datetime]::MinValue

function Get-DirectorySize {
    param (
        [string]$DirPath,
        [int]$CurrentDepth,
        [string]$Indent
    )

    # Update the progress bar, throttled to at most once every 150 ms.
    # Recalculate percentage and ETA each time we start a new top-level subdirectory.
    if ($script:topLevelTotal -gt 0) {
        $now = [datetime]::UtcNow
        if ($CurrentDepth -eq 1) {
            $elapsed = $now - $script:scanStartTime
            $script:progressPct = [int](($script:topLevelDone / $script:topLevelTotal) * 100)
            if ($script:topLevelDone -gt 0) {
                $secsPerDir = $elapsed.TotalSeconds / $script:topLevelDone
                $script:progressEta = [int]($secsPerDir * ($script:topLevelTotal - $script:topLevelDone))
            }
            $script:topLevelDone++
        }
        if (($now - $script:lastProgressUpdate).TotalMilliseconds -gt 150) {
            Write-Progress -Activity $script:progressActivity `
                -Status "Scanning: $DirPath" `
                -PercentComplete $script:progressPct `
                -SecondsRemaining $script:progressEta
            $script:lastProgressUpdate = $now
        }
    }

    $totalSize = [long]0
    $subDirs   = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()

    # Single .NET enumeration pass — significantly faster than two Get-ChildItem calls.
    # DirectoryInfo.EnumerateFileSystemInfos() streams results lazily without buffering.
    try {
        foreach ($item in ([System.IO.DirectoryInfo]::new($DirPath)).EnumerateFileSystemInfos()) {
            if ($item -is [System.IO.DirectoryInfo]) {
                $subDirs.Add($item)
            } elseif ($item -is [System.IO.FileInfo]) {
                $totalSize += $item.Length
            }
            # else: skip other special file types (e.g. reparse points not resolved as file/dir)
        }
    }
    catch {
        # Access denied or other error - skip silently
    }

    $subResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($subDir in $subDirs) {
        $subSize = Get-DirectorySize -DirPath $subDir.FullName -CurrentDepth ($CurrentDepth + 1) -Indent "$Indent    "
        $totalSize += $subSize.Size
        # Only include in display results when within the requested depth
        if (($Depth -eq -1) -or ($CurrentDepth -lt $Depth)) {
            $subResults.Add($subSize)
        }
    }

    return [PSCustomObject]@{
        Path        = $DirPath
        Size        = $totalSize
        Indent      = $Indent
        Children    = ($subResults | Sort-Object -Property Size -Descending)
        Depth       = $CurrentDepth
    }
}

function Show-Tree {
    param (
        [PSCustomObject]$Node,
        [bool]$IsRoot = $false
    )

    $displayName = if ($IsRoot) { $Node.Path } else { Split-Path $Node.Path -Leaf }

    if ($Node.Size -ge $MinSize) {
        Write-Output ("{0}{1}  {2}" -f $Node.Indent, (Format-Size $Node.Size), $displayName)
    }

    foreach ($child in $Node.Children) {
        $canDisplay = ($Depth -eq -1) -or ($child.Depth -le $Depth)
        if ($canDisplay -and $child.Size -ge $MinSize) {
            Show-Tree -Node $child
        }
    }
}

# Validate the path
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Error "Path '$Path' does not exist or is not a directory."
    exit 1
}

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path

Write-Host "Scanning '$resolvedPath' ..." -ForegroundColor Cyan
Write-Host ""

# Pre-count immediate subdirectories so we can show meaningful progress/ETA
$script:scanStartTime    = [datetime]::UtcNow
$script:progressActivity = "Scanning '$resolvedPath'"
try {
    $script:topLevelTotal = @(Get-ChildItem -LiteralPath $resolvedPath -Directory -Force -ErrorAction SilentlyContinue).Count
} catch {
    $script:topLevelTotal = 0
}

$tree = Get-DirectorySize -DirPath $resolvedPath -CurrentDepth 0 -Indent ""
Write-Progress -Activity $script:progressActivity -Completed
Show-Tree -Node $tree -IsRoot $true

Write-Host ""
Write-Host ("Total: {0}" -f (Format-Size $tree.Size)) -ForegroundColor Green
