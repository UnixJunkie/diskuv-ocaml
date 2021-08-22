param (
    [Parameter(Mandatory = $true)]
    $Path,
    $TimeoutMs = 3000,
    [switch]$Recursive,
    [switch]$EventChanged,
    [switch]$EventRenamed,
    [switch]$EventCreated,
    [switch]$EventDeleted
)

# See https://docs.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher?view=net-5.0

$Watcher = New-Object System.IO.FileSystemWatcher

$Watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName

$Watcher.Path = $Path
$Watcher.IncludeSubdirectories = $Recursive
$Watcher.EnableRaisingEvents = $false

$ChangeType = 0
if ($EventChanged) {
    $ChangeType = [System.IO.WatcherChangeTypes]::Changed
}

if ($EventRenamed) {
    $ChangeType = $ChangeType -bor [System.IO.WatcherChangeTypes]::Renamed
}

if ($EventCreated) {
    $ChangeType = $ChangeType -bor [System.IO.WatcherChangeTypes]::Created
}

if ($EventDeleted) {
    $ChangeType = $ChangeType -bor [System.IO.WatcherChangeTypes]::Deleted
}

while ($true) {
    $ChangedResult = $Watcher.WaitForChanged($ChangeType, $TimeoutMs);
    if ($ChangedResult.TimedOut) {
        continue
    }
    Write-Host (Join-Path -Path $Path -ChildPath $ChangedResult.Name)
}
