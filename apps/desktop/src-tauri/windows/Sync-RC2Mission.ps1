param(
    [Parameter(Mandatory = $true)]
    [string]$SourceKmz,

    [string]$DeviceHint = 'DJI',

    [string[]]$MissionFolderNames = @('wayline_mission', 'waypoint')
)

$ErrorActionPreference = 'Stop'

function Get-Items($Folder) {
    @($Folder.Items())
}

function Get-FolderFromItem($Item) {
    if ($null -eq $Item -or -not $Item.IsFolder) {
        return $null
    }

    return $Item.GetFolder()
}

function Find-Rc2Device($Shell, $Hint) {
    $computer = $Shell.Namespace('shell:MyComputerFolder')
    if ($null -eq $computer) {
        throw 'Cannot access the Windows device namespace.'
    }

    $devices = Get-Items $computer | Where-Object {
        $_.IsFolder -and ($_.Name -match 'DJI|RC 2|KATMAI')
    }

    if (-not $devices -or $devices.Count -eq 0) {
        $devices = Get-Items $computer | Where-Object {
            $_.IsFolder -and $_.Path -like '::*'
        }
    }

    if ($Hint) {
        $matched = @($devices | Where-Object { $_.Name -like "*$Hint*" })
        if ($matched.Count -gt 0) {
            $devices = $matched
        }
    }

    if (-not $devices -or $devices.Count -eq 0) {
        throw 'RC 2 device not detected. Confirm the controller is connected over USB and visible in Windows.'
    }

    return $devices[0]
}

function Find-FoldersByName($Folder, $Names, $Depth = 0, $MaxDepth = 8) {
    $results = @()

    if ($Depth -gt $MaxDepth) {
        return $results
    }

    foreach ($item in Get-Items $Folder) {
        if (-not $item.IsFolder) {
            continue
        }

        if ($Names -contains $item.Name) {
            $results += ,(Get-FolderFromItem $item)
        }

        $childFolder = Get-FolderFromItem $item
        if ($null -ne $childFolder) {
            $results += Find-FoldersByName $childFolder $Names ($Depth + 1) $MaxDepth
        }
    }

    return $results
}

function Collect-KmzCandidates($Folder, $Depth = 0, $MaxDepth = 6) {
    $results = @()

    if ($Depth -gt $MaxDepth) {
        return $results
    }

    foreach ($item in Get-Items $Folder) {
        if ($item.IsFolder) {
            $childFolder = Get-FolderFromItem $item
            if ($null -ne $childFolder) {
                $results += Collect-KmzCandidates $childFolder ($Depth + 1) $MaxDepth
            }
            continue
        }

        if ($item.Name -notlike '*.kmz') {
            continue
        }

        $results += [PSCustomObject]@{
            Item = $item
            Folder = $Folder
            DateModified = [datetime]($item.ExtendedProperty('System.DateModified'))
        }
    }

    return $results
}

$resolvedSource = (Resolve-Path $SourceKmz).Path
$shell = New-Object -ComObject Shell.Application
$deviceItem = Find-Rc2Device $shell $DeviceHint
$deviceFolder = Get-FolderFromItem $deviceItem

if ($null -eq $deviceFolder) {
    throw 'The RC 2 device was detected but its folders are not accessible.'
}

$missionFolders = @(Find-FoldersByName $deviceFolder $MissionFolderNames)
if ($missionFolders.Count -eq 0) {
    throw 'DJI Fly mission folder not found. Create a placeholder mission in DJI Fly on RC 2 first.'
}

$candidates = @()
foreach ($folder in $missionFolders) {
    $candidates += Collect-KmzCandidates $folder
}

if ($candidates.Count -eq 0) {
    throw 'No placeholder .kmz mission file was found. Create a fresh placeholder mission in DJI Fly first.'
}

$target = $candidates |
    Sort-Object DateModified -Descending |
    Select-Object -First 1

$targetName = $target.Item.Name
$parentFolder = $target.Folder
$tempCopy = Join-Path ([System.IO.Path]::GetTempPath()) $targetName
Copy-Item $resolvedSource $tempCopy -Force

try {
    $existing = $parentFolder.ParseName($targetName)
    if ($null -ne $existing) {
        $existing.InvokeVerb('delete')
        Start-Sleep -Milliseconds 600
    }
} catch {
}

$copyFlags = 4 + 16 + 512 + 1024
$parentFolder.CopyHere($tempCopy, $copyFlags)
Start-Sleep -Seconds 2

Write-Output ("Synced to RC 2: {0}" -f $targetName)
