# PS-TreeSize

A PowerShell script that scans directories and displays a hierarchical tree view of folder and file sizes, similar to [TreeSize Free](https://www.jam-software.com/treesize_free).

## Features

- Recursively scans all subdirectories and calculates their total sizes
- **Opens an interactive, collapsible tree window by default on Windows** (requires no extra flags)
- Displays results in a tree layout sorted by size (largest first)
- Human-readable size formatting (B, KB, MB, GB, TB)
- Defaults to the system drive (`$env:SystemDrive`) when no path is provided
- Optional depth limit to control how many levels are displayed
- Optional minimum size filter to hide small entries
- Gracefully handles permission-denied errors

## Usage

```powershell
.\Get-TreeSize.ps1 [[-Path] <string>] [-Depth <int>] [-MinSize <long>] [-NoGui]
```

### Parameters

| Parameter  | Description                                                         | Default              |
|------------|---------------------------------------------------------------------|----------------------|
| `-Path`    | Root directory to scan                                              | System drive (`C:\`) |
| `-Depth`   | Maximum directory depth to display (`-1` = unlimited)              | `-1`                 |
| `-MinSize` | Minimum size in bytes to display an entry (supports `1MB`, `1GB`)  | `0`                  |
| `-NoGui`   | Print results to the console instead of opening the tree window     | *(GUI is default on Windows)* |

### Examples

```powershell
# Scan the system drive – opens the tree window on Windows (default)
.\Get-TreeSize.ps1

# Scan a specific directory
.\Get-TreeSize.ps1 -Path "C:\Users"

# Scan with a depth limit of 3 levels
.\Get-TreeSize.ps1 -Path "D:\" -Depth 3

# Only show entries larger than 100 MB
.\Get-TreeSize.ps1 -Path "C:\Windows" -MinSize 100MB

# Print to the console instead of opening the GUI window
.\Get-TreeSize.ps1 -Path "C:\Users" -NoGui
```

### Console output (`-NoGui`)

```
Scanning 'C:\Users' ...

   1.23 GB  C:\Users
      856.42 MB  John
         512.10 MB  Documents
         ...
      389.21 MB  Public
         ...

Total:    1.23 GB
```

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Run as Administrator for full access to system directories