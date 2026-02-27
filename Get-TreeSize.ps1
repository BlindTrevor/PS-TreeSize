<#
.SYNOPSIS
    Scans directories and displays a tree view of folder and file sizes, similar to TreeSize Free.

.DESCRIPTION
    Get-TreeSize recursively scans a specified directory (or the system drive by default) and
    displays a hierarchical tree view of all folders and their sizes, sorted by size descending.
    On Windows the script opens an interactive, collapsible Windows Forms tree window by default.
    Pass -NoGui to print the tree to the console instead. On non-Windows systems the console output
    is always used; pass -Gui to explicitly request Windows Forms (which will raise an error).

.PARAMETER Path
    The root directory to scan. Defaults to the system drive (e.g., C:\).

.PARAMETER Depth
    Maximum depth of the directory tree to display. Defaults to unlimited (-1).

.PARAMETER MinSize
    Minimum size in bytes to display an entry. Defaults to 0.

.PARAMETER Gui
    Forces the Windows Forms GUI window even when it would otherwise not be shown.
    Exists primarily for clarity; on Windows the GUI is the default.

.PARAMETER NoGui
    Suppresses the Windows Forms GUI and prints the tree to the console instead.
    Useful for scripting, piping, or running on Windows without a display.

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

.EXAMPLE
    .\Get-TreeSize.ps1 -Path "C:\Users" -Gui
    Scans C:\Users and displays results in an interactive, collapsible Windows Forms tree window.
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string]$Path = "$($env:SystemDrive)\",

    [Parameter()]
    [int]$Depth = -1,

    [Parameter()]
    [long]$MinSize = 0,

    [Parameter()]
    [switch]$Gui,

    [Parameter()]
    [switch]$NoGui
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
$script:progressEta           = -1
$script:progressEtaComputedAt = [datetime]::MinValue
$script:progressActivity      = ""
$script:lastProgressUpdate    = [datetime]::MinValue

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
                $script:progressEta           = [Math]::Round($secsPerDir * ($script:topLevelTotal - $script:topLevelDone))
                $script:progressEtaComputedAt = $now
            }
            $script:topLevelDone++
        }
        if (($now - $script:lastProgressUpdate).TotalMilliseconds -gt 150) {
            # Count the ETA down in real time so it never stays frozen between depth-1 updates.
            # Once the original estimate is exhausted, suppress the display (-1) rather than
            # showing a misleading stale value.
            $displayEta = if ($script:progressEta -ge 0 -and $script:progressEtaComputedAt -ne [datetime]::MinValue) {
                $remaining = $script:progressEta - ($now - $script:progressEtaComputedAt).TotalSeconds
                if ($remaining -gt 0) { [Math]::Round($remaining) } else { -1 }
            } else {
                $script:progressEta
            }
            Write-Progress -Activity $script:progressActivity `
                -Status "Scanning: $DirPath" `
                -PercentComplete $script:progressPct `
                -SecondsRemaining $displayEta
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

function Add-TreeViewNodes {
    # Recursively populate a Windows Forms TreeNodeCollection from our scan result tree.
    param (
        [System.Windows.Forms.TreeNodeCollection]$Nodes,
        [PSCustomObject]$Node,
        [bool]$IsRoot = $false,
        [long]$ParentSize = 0
    )

    $displayName = if ($IsRoot) { $Node.Path } else { Split-Path $Node.Path -Leaf }
    $pct = if ($IsRoot -or $ParentSize -le 0) { 100.0 } else { [Math]::Round($Node.Size / $ParentSize * 100.0, 1) }
    $tvNode = [System.Windows.Forms.TreeNode]::new(
        ("{0}  {1}" -f (Format-Size $Node.Size), $displayName)
    )
    $tvNode.Tag         = $pct
    $tvNode.ToolTipText = if ($IsRoot) { '' } else { "$pct% of parent" }

    foreach ($child in $Node.Children) {
        $canDisplay = ($Depth -eq -1) -or ($child.Depth -le $Depth)
        if ($canDisplay -and $child.Size -ge $MinSize) {
            Add-TreeViewNodes -Nodes $tvNode.Nodes -Node $child -ParentSize $Node.Size
        }
    }

    $Nodes.Add($tvNode) | Out-Null
    return $tvNode
}

function Show-TreeGui {
    param ([PSCustomObject]$RootNode)

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
    }
    catch {
        Write-Error "Windows Forms is not available on this system. $_"
        return
    }

    $form                = [System.Windows.Forms.Form]::new()
    $form.Text           = "PS-TreeSize - $($RootNode.Path)"
    $form.Size           = [System.Drawing.Size]::new(700, 550)
    $form.MinimumSize    = [System.Drawing.Size]::new(400, 300)
    $form.StartPosition  = 'CenterScreen'

    $tv               = [System.Windows.Forms.TreeView]::new()
    $tv.Dock          = [System.Windows.Forms.DockStyle]::Fill
    $tv.Font          = [System.Drawing.Font]::new('Consolas', 10)
    $tv.ShowLines     = $true
    $tv.ShowPlusMinus = $true
    $tv.Scrollable    = $true
    $tv.DrawMode      = [System.Windows.Forms.TreeViewDrawMode]::OwnerDrawText
    $tv.ShowNodeToolTips = $true

    $barBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(100, 70, 130, 180))
    $tv.Add_DrawNode({
        param($drawSender, $drawE)

        $pct        = if ($null -ne $drawE.Node.Tag) { [double]$drawE.Node.Tag } else { 0.0 }
        $isSelected = ($drawE.State -band [System.Windows.Forms.TreeNodeStates]::Selected) -ne 0

        # Draw background
        $bgBrush = if ($isSelected) { [System.Drawing.SystemBrushes]::Highlight } else { [System.Drawing.SystemBrushes]::Window }
        $drawE.Graphics.FillRectangle($bgBrush, $drawE.Bounds)

        # Draw percentage bar behind the text
        if ($pct -gt 0 -and $drawE.Bounds.Width -gt 0) {
            $barWidth = [int]($drawE.Bounds.Width * $pct / 100.0)
            $drawE.Graphics.FillRectangle($barBrush, $drawE.Bounds.X, $drawE.Bounds.Y, $barWidth, $drawE.Bounds.Height)
        }

        # Draw node text
        $fgColor = if ($isSelected) { [System.Drawing.SystemColors]::HighlightText } else { [System.Drawing.SystemColors]::WindowText }
        $flags   = [System.Windows.Forms.TextFormatFlags]::Left -bor
                   [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                   [System.Windows.Forms.TextFormatFlags]::NoPrefix
        [System.Windows.Forms.TextRenderer]::DrawText($drawE.Graphics, $drawE.Node.Text, $drawE.Node.TreeView.Font, $drawE.Bounds, $fgColor, $flags)

        # Draw focus rectangle when the node has keyboard focus
        if (($drawE.State -band [System.Windows.Forms.TreeNodeStates]::Focused) -ne 0) {
            [System.Windows.Forms.ControlPaint]::DrawFocusRectangle($drawE.Graphics, $drawE.Bounds, $fgColor, [System.Drawing.SystemColors]::Window)
        }
    })

    $statusBar            = [System.Windows.Forms.Panel]::new()
    $statusBar.Dock       = [System.Windows.Forms.DockStyle]::Bottom
    $statusBar.Height     = 30
    $statusBar.BackColor  = [System.Drawing.SystemColors]::Control

    $statusLabel           = [System.Windows.Forms.Label]::new()
    $statusLabel.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $statusLabel.Text      = "Total: $(Format-Size $RootNode.Size)"
    $statusLabel.Font      = [System.Drawing.Font]::new('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $statusLabel.Padding   = [System.Windows.Forms.Padding]::new(6, 0, 0, 0)
    $statusBar.Controls.Add($statusLabel)

    Add-TreeViewNodes -Nodes $tv.Nodes -Node $RootNode -IsRoot $true | Out-Null

    # Add controls in reverse dock order so Fill occupies the remaining space correctly
    $form.Controls.Add($tv)
    $form.Controls.Add($statusBar)

    $form.ShowDialog() | Out-Null
    $barBrush.Dispose()
    $form.Dispose()
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

# $IsWindows is only defined in PowerShell 6+; on Windows PowerShell 5.x we're always on Windows.
$isWindowsPlatform = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

# On Windows the GUI is the default; pass -NoGui to get plain console output.
# On non-Windows the console is the default; pass -Gui to explicitly request Windows Forms
# (which will raise an error because WinForms is unavailable).
$useGui = ($isWindowsPlatform -and -not $NoGui) -or $Gui

if ($useGui) {
    if (-not $isWindowsPlatform) {
        Write-Error "The -Gui switch requires Windows and Windows Forms support."
        exit 1
    }
    Show-TreeGui -RootNode $tree
} else {
    Show-Tree -Node $tree -IsRoot $true

    Write-Host ""
    Write-Host ("Total: {0}" -f (Format-Size $tree.Size)) -ForegroundColor Green
}
