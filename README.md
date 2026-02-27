# PS-TreeSize

A PowerShell script that scans directories and displays a hierarchical tree view of folder and file sizes, similar to [TreeSize Free](https://www.jam-software.com/treesize_free).

## Features

- Recursively scans all subdirectories and calculates their total sizes
- **Opens an interactive, collapsible tree window by default on Windows** (requires no extra flags)
- Pac-Man animation in the console while the scan is running 🟡
- Each row shows a proportional size bar so large folders stand out at a glance
- Right-click any folder to open it in Explorer, copy its path, or move it to the Recycle Bin
- Displays results sorted by size (largest first) at every level
- Human-readable size formatting (B, KB, MB, GB, TB)
- Defaults to the system drive (`$env:SystemDrive`) when no path is provided
- Optional depth limit to control how many levels are displayed
- Optional minimum size filter to hide small entries
- Gracefully handles permission-denied errors

## Screenshots

### GUI mode (Windows default)

![PS-TreeSize GUI showing a collapsible tree of folder sizes with proportional blue bars](https://github.com/user-attachments/assets/1e012be7-24d1-4aaa-8a50-5a841663886f)

### Console mode (`-NoGui`)

![PS-TreeSize console output showing an indented tree of folder sizes](https://github.com/user-attachments/assets/9940f040-cf53-400a-9ec0-4a19eec8110b)

## Usage

```powershell
.\Get-TreeSize.ps1 [[-Path] <string>] [-Depth <int>] [-MinSize <long>] [-Gui] [-NoGui]
```

### Parameters

| Parameter  | Description                                                         | Default              |
|------------|---------------------------------------------------------------------|----------------------|
| `-Path`    | Root directory to scan                                              | System drive (`C:\`) |
| `-Depth`   | Maximum directory depth to display (`-1` = unlimited)              | `-1`                 |
| `-MinSize` | Minimum size in bytes to display an entry (supports `1MB`, `1GB`)  | `0`                  |
| `-Gui`     | Force the Windows Forms GUI window (useful for clarity; GUI is already the default on Windows) | *(see below)* |
| `-NoGui`   | Print results to the console instead of opening the GUI window     | *(GUI is default on Windows)* |

> **Platform behaviour:** on Windows the GUI opens automatically unless `-NoGui` is passed. On Linux/macOS the console output is always used; passing `-Gui` on a non-Windows system raises an error.

### Examples

```powershell
# Scan the system drive – opens the interactive tree window on Windows (default)
.\Get-TreeSize.ps1

# Scan a specific directory
.\Get-TreeSize.ps1 -Path "C:\Users"

# Scan with a depth limit of 3 levels
.\Get-TreeSize.ps1 -Path "D:\" -Depth 3

# Only show entries larger than 100 MB
.\Get-TreeSize.ps1 -Path "C:\Windows" -MinSize 100MB

# Print to the console instead of opening the GUI window
.\Get-TreeSize.ps1 -Path "C:\Users\Demo" -NoGui
```

### Console output (`-NoGui`)

```
Scanning 'C:\Users\Demo' ...

  300.56 MB  C:\Users\Demo
      175.00 MB  Videos
       75.00 MB  Downloads
       24.00 MB  Music
       21.56 MB  Documents
           15.06 MB  Personal
            6.50 MB  Work
                6.00 MB  Reports
        5.00 MB  Pictures
            5.00 MB  Vacation

Total:   300.56 MB
```

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Run as Administrator for full access to system directories