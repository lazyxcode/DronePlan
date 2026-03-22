param(
    [Parameter(Mandatory = $true)]
    [string]$SourceKmz,

    [string]$DeviceHint = 'DJI'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helper: safely enumerate Shell folder items as an array
# ---------------------------------------------------------------------------
function Get-Items($Folder) {
    @($Folder.Items())
}

function Get-FolderFromItem($Item) {
    if ($null -eq $Item -or -not $Item.IsFolder) { return $null }
    return $Item.GetFolder()
}

# ---------------------------------------------------------------------------
# Step 1 – Locate the DJI RC 2 device in "This PC"
# ---------------------------------------------------------------------------
function Find-Rc2Device($Shell, $Hint) {
    $computer = $Shell.Namespace('shell:MyComputerFolder')
    if ($null -eq $computer) {
        throw 'Cannot access the Windows device namespace.'
    }

    # Primary: match by known DJI device names
    $devices = @(Get-Items $computer | Where-Object {
        $_.IsFolder -and ($_.Name -match 'DJI|RC 2|RC Pro|KATMAI')
    })

    # Fallback: any MTP/portable device (GUID-like shell path)
    if ($devices.Count -eq 0) {
        $devices = @(Get-Items $computer | Where-Object {
            $_.IsFolder -and $_.Path -like '::{*'
        })
    }

    if ($Hint) {
        $matched = @($devices | Where-Object { $_.Name -like "*$Hint*" })
        if ($matched.Count -gt 0) { $devices = $matched }
    }

    if ($devices.Count -eq 0) {
        throw 'RC 2 device not detected. Connect the controller via USB and ensure it appears in Windows Explorer.'
    }

    return $devices[0]
}

# ---------------------------------------------------------------------------
# Step 2 – Navigate to the DJI Fly waypoint folder on the device.
#
# Rainbow Cloud confirmed path:
#   <device>\Internal Storage\Android\data\dji.go.v5\files\waypoint
#
# We try the canonical path first (fast), then fall back to a name-based
# recursive search in case the storage label differs.
# ---------------------------------------------------------------------------
$WaypointRelPath = 'Internal Storage\Android\data\dji.go.v5\files\waypoint'
$WaypointFolderNames = @('waypoint', 'wayline_mission')

function Navigate-ToPath($RootFolder, $RelPath) {
    $parts = $RelPath -split '\\'
    $current = $RootFolder
    foreach ($part in $parts) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $child = $current.ParseName($part)
        if ($null -eq $child -or -not $child.IsFolder) { return $null }
        $current = $child.GetFolder()
        if ($null -eq $current) { return $null }
    }
    return $current
}

function Find-FoldersByName($Folder, $Names, $Depth = 0, $MaxDepth = 9) {
    $results = @()
    if ($Depth -gt $MaxDepth) { return $results }

    foreach ($item in Get-Items $Folder) {
        if (-not $item.IsFolder) { continue }

        if ($Names -contains $item.Name) {
            $f = Get-FolderFromItem $item
            if ($null -ne $f) { $results += $f }
        }

        $child = Get-FolderFromItem $item
        if ($null -ne $child) {
            $results += Find-FoldersByName $child $Names ($Depth + 1) $MaxDepth
        }
    }
    return $results
}

# ---------------------------------------------------------------------------
# Step 3 – Find the newest UUID mission sub-folder that contains a .kmz file.
#
# DJI Fly stores each waypoint mission as:
#   waypoint\<UUID>\<UUID>.kmz
#
# We identify the target UUID folder (most recently modified) and overwrite
# the .kmz inside it – exactly what Rainbow Cloud's MtpCopyTool does.
# ---------------------------------------------------------------------------
function Find-NewestMissionUuidFolder($WaypointFolder) {
    $best = $null
    $bestTime = [datetime]::MinValue

    foreach ($item in Get-Items $WaypointFolder) {
        if (-not $item.IsFolder) { continue }

        $uuidFolder = Get-FolderFromItem $item
        if ($null -eq $uuidFolder) { continue }

        # Check that this UUID folder contains at least one .kmz
        $hasKmz = @(Get-Items $uuidFolder | Where-Object { $_.Name -like '*.kmz' }).Count -gt 0
        if (-not $hasKmz) { continue }

        try {
            $modTime = [datetime]($item.ExtendedProperty('System.DateModified'))
        } catch {
            $modTime = [datetime]::MinValue
        }

        if ($modTime -gt $bestTime) {
            $bestTime = $modTime
            $best = [PSCustomObject]@{
                UuidName   = $item.Name
                Folder     = $uuidFolder
            }
        }
    }
    return $best
}

# ---------------------------------------------------------------------------
# Step 4 – Copy the source KMZ into the UUID folder.
#
# Rainbow's method (verified via binary analysis of MtpCopyTool.exe):
#   1. Rename the source .kmz to <UUID>.kmz in a local temp directory.
#   2. Call Shell.Folder.CopyHere() with flags 4+16+512+1024.
#      Flags: 4=no progress UI, 16=yes to all, 512=no error UI, 1024=no undo.
#   3. Wait briefly for the MTP transfer to complete.
#
# We do NOT attempt to delete the existing file first – deletion over MTP is
# unreliable and causes the write to silently fail on many RC 2 firmware
# versions. CopyHere with flag 16 ("yes to all / replace") handles the
# overwrite atomically through the Windows Shell.
# ---------------------------------------------------------------------------
function Copy-KmzToDevice($UuidFolder, $UuidName, $SourceKmzPath) {
    $targetName = "${UuidName}.kmz"
    $tempDir    = Join-Path ([System.IO.Path]::GetTempPath()) 'DronePlan-rc2sync'
    $null = New-Item -ItemType Directory -Force -Path $tempDir

    # Rename to match the UUID so Windows Shell places it with the right name
    $tempKmz = Join-Path $tempDir $targetName
    Copy-Item $SourceKmzPath $tempKmz -Force

    $copyFlags = 4 + 16 + 512 + 1024   # silent, replace-all, no-errors, no-undo
    $UuidFolder.CopyHere($tempKmz, $copyFlags)

    # MTP transfers are async under the Shell; wait for completion
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $placed = $UuidFolder.ParseName($targetName)
        if ($null -ne $placed) { break }
    }

    return $targetName
}

# ===========================================================================
# Main
# ===========================================================================
$resolvedSource = (Resolve-Path $SourceKmz).Path

$shell       = New-Object -ComObject Shell.Application
$deviceItem  = Find-Rc2Device $shell $DeviceHint
$deviceFolder = Get-FolderFromItem $deviceItem

if ($null -eq $deviceFolder) {
    throw 'RC 2 device detected but its storage is not accessible. Unlock the controller screen and try again.'
}

# Try canonical path first (fast)
$waypointFolder = Navigate-ToPath $deviceFolder $WaypointRelPath

# Fall back to recursive name search
if ($null -eq $waypointFolder) {
    $found = @(Find-FoldersByName $deviceFolder $WaypointFolderNames)
    if ($found.Count -eq 0) {
        throw (
            "DJI Fly mission folder not found on RC 2.`n" +
            "Open DJI Fly on the controller, create one placeholder waypoint mission, then retry."
        )
    }
    $waypointFolder = $found[0]
}

$mission = Find-NewestMissionUuidFolder $waypointFolder
if ($null -eq $mission) {
    throw (
        "No existing waypoint mission found in the DJI Fly waypoint folder.`n" +
        "Open DJI Fly on the controller, create one placeholder waypoint mission, then retry."
    )
}

$syncedName = Copy-KmzToDevice $mission.Folder $mission.UuidName $resolvedSource

Write-Output ("Synced `"$syncedName`" to RC 2 ({0})" -f $deviceItem.Name)
