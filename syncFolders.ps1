<#
.SYNOPSIS
This script synchronizes files between a source folder and a replica folder.
Author: Fratisek Zunt
Created with the assistance of ChatGPT and GitHub Copilot.

.DESCRIPTION
This script synchronizes files between a source folder and a replica folder. It copies new files from the source folder to the replica folder, updates files in the replica folder if the content is different, and removes files and folders from the replica folder that are not present in the source folder.
1. The script takes three parameters: sourceFolder, replicaFolder, and logPath.
2. The script creates a log file in the specified logPath or defaults to /var/log/replica_sync or C:\logs\replica_sync.
3. The script checks if the source folder exists and if the replica folder exists. If the replica folder does not exist, it creates it.
4. The script iterates through each item in the source folder and copies new files to the replica folder, updates files in the replica folder if the content is different, and logs any errors encountered during the process.
5. The script cleans up the replica folder by removing files and empty folders not present in the source folder.

.PARAMETER sourceFolder
The path to the source folder. This parameter is mandatory.

.PARAMETER replicaFolder
The path to the replica folder. This parameter is mandatory.

.PARAMETER logPath
The path to the log file. This parameter is optional, and defaults to /var/log/replica_sync or C:\logs\replica_sync.

.EXAMPLE
./syncFolders.ps1 -sourceFolder "/users/user1/source" -replicaFolder "/users/user1/replica" -logPath "/users/user1/logs"

.NOTES
Ensure that the paths provided exist and that you have the necessary permissions to read from the source folder and write to the replica folder.
#>
param(
  [Parameter(Mandatory = $true, HelpMessage = "Enter the path to the source folder.")]
  [string]$sourceFolder,
  [Parameter(Mandatory = $true, HelpMessage = "Enter the path to the replica folder.")]
  [string]$replicaFolder,
  [Parameter(Mandatory = $false, HelpMessage = "Enter the path to the log. Default is /var/log/replica_sync or C:\logs\replica_sync.")]
  [string]$logPath
)
# Function to log messages to console and file
function LogMessage {
  param(
    [string]$message
  )
  $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $logMessage = "[$date] $message"
  Write-Host $logMessage
  $logMessage | Out-File -FilePath $logFilePath -Append
}
# Check Directory separator
$slash = [System.IO.Path]::DirectorySeparatorChar
# Check linux / windows environment
if (-not $logPath -and $slash -eq "/") {
  $logPath = "/var/log/replica_sync"
  Write-Output "Log path is: $logPath"
}
elseif (-not $logPath -and $slash -eq "\") {
  $logPath = "C:\logs\replica_sync"
  write-Output "Log path is: $logPath"
}
else {
  Write-Output "Log path is: $logPath"
}
# create log file name and log file path
$logFileName = $sourceFolder.split("$slash")[-1] + "_" + $replicaFolder.split("$slash")[-1] + "_sync.log"
$logFilePath = Join-Path -Path $logPath -ChildPath $logFileName
# test log path
if (-not (Test-Path $logPath -PathType Container)) {
  # If log path does not exist, create it
  Write-Output "Log path does not exist, creating: $logPath"
  try {
    New-Item -Path $logPath -ItemType Directory  -ErrorAction Stop | Out-Null
  }
  catch {
    Write-Error $_.Exception.Message
    exit 1
  }
}
# check log file path
if (-not (Test-Path $logFilePath)) {
  # If log file does not exist, create it
  Write-Output "Log file does not exist, creating: $logFilePath"
  try {
    New-Item -Path $logFilePath -ItemType File -ErrorAction Stop | Out-Null
  }
  catch {
    Write-Error $_.Exception.Message
    exit 1
  }
}
LogMessage "### Starting synchronization ###"
LogMessage "Source: $sourceFolder"
LogMessage "Replica: $replicaFolder"
# Check if source folder exists
if (-not (Test-Path $sourceFolder -PathType Container)) {
  LogMessage "Source folder does not exist: $sourceFolder"
  exit 1
}
# Check if replica folder exists, create if not
if (-not (Test-Path $replicaFolder -PathType Container)) {
  LogMessage "Replica folder does not exist, creating: $replicaFolder"
  try {
    New-Item -Path $replicaFolder -ItemType Directory -ErrorAction Stop | Out-Null
  }
  catch {
    LogMessage "Error creating folder: $($_.Exception.Message)"
    exit 1
  }
}
# Get all files and folders in source folder
$sourceItems = Get-ChildItem -Path $sourceFolder -Recurse
# Iterate through each item in source folder
foreach ($item in $sourceItems) {
  $relativePath = $item.FullName.Substring($sourceFolder.Length + 1)
  $replicaItemPath = Join-Path -Path $replicaFolder -ChildPath $relativePath
  if ($item.PSIsContainer) {
    # If it's a folder
    if (-not (Test-Path $replicaItemPath -PathType Container)) {
      LogMessage "Creating folder: $replicaItemPath"
      try {
        New-Item -Path $replicaItemPath -ItemType Directory | Out-Null
      }
      catch {
        LogMessage "Error creating folder: $($_.Exception.Message)"
      }
    }
  }
  else {
    # If it's a file
    if (-not (Test-Path $replicaItemPath)) {
      # If file does not exist in replica
      LogMessage "Copying file: $($item.FullName) to $replicaItemPath"
      try {
        Copy-Item -Path $item.FullName -Destination $replicaItemPath -Force
      }
      catch {
        LogMessage "Error copying file: $($_.Exception.Message)"
      }
    }
    else {
      # If file exists in replica
      $sourceFileHash = Get-FileHash -Path $item.FullName
      $replicaFileHash = Get-FileHash -Path $replicaItemPath
      if ($sourceFileHash.Hash -ne $replicaFileHash.Hash) {
        # If file content is different
        LogMessage "Updating file: $replicaItemPath"
        try {
          Copy-Item -Path $item.FullName -Destination $replicaItemPath -Force
        }
        catch {
          LogMessage "Error updating file: $($_.Exception.Message)"
        }
      }
    }
  }
}
# Clean up replica folder (remove files and empty folders not present in source)
$containers = @()
$replicaItems = Get-ChildItem -Path $replicaFolder -Recurse
foreach ($item in $replicaItems) {
  $relativePath = $item.FullName.Substring($replicaFolder.Length + 1)
  $sourceItemPath = Join-Path -Path $sourceFolder -ChildPath $relativePath
  if (-not (Test-Path $sourceItemPath)) {
    # If item does not exist in source
    if ($item.PSIsContainer) {
      # If it's a folder colect it for later processing
      $containers += $item
    }
    else {
      # If it's a file remove it
      LogMessage "Removing file: $($item.FullName)"
      try {
        Remove-Item -Path $item.FullName -Force -Confirm:$false
      }
      catch {
        LogMessage $_.Exception.Message
      }
    }
  }
}
# Process non-empty containers and remove them if they contain no valid children
if ($containers.Count -gt 0) {
  do {
    $notEmptyContainers = @()
    foreach ($container in $containers) {
      if ($container.GetFileSystemInfos().Count -eq 0) {
        LogMessage "Removing folder: $($container.FullName)"
        try {
          Remove-Item -Path $container.FullName -Force -Confirm:$false
        }
        catch {
          LogMessage $_.Exception.Message
        }
      }
      else {
        $notEmptyContainers += $container
      }
    }
    $containers = $notEmptyContainers
  } while ($containers.Count -gt 0)
}
LogMessage "=== Synchronization complete. ==="