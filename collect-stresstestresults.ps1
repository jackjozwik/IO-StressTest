# File: Collect-StressTestResults.ps1
param(
    [Parameter(Mandatory=$true)]
    [string]$ExcelPath,
    [Parameter(Mandatory=$true)]
    [string]$OutputPath
)

# Import Excel module if needed
if (-not (Get-Module -Name ImportExcel)) {
    Install-Module -Name ImportExcel -Force -Scope CurrentUser
}

# Create results directory
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$resultsPath = Join-Path $OutputPath $timestamp
New-Item -ItemType Directory -Force -Path $resultsPath | Out-Null

# Read computer names
$excel = Import-Excel -Path $ExcelPath
$firstCol = $excel[0].PSObject.Properties.Name | Select-Object -First 1
$computers = $excel | Select-Object -ExpandProperty $firstCol | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$results = @()

foreach ($computer in $computers) {
    Write-Host "Collecting results from $computer..."
    
    try {
        # Create computer-specific directory
        $computerPath = Join-Path $resultsPath $computer
        New-Item -ItemType Directory -Force -Path $computerPath | Out-Null
        
        # Get most recent test folder
        $remoteResults = Invoke-Command -ComputerName $computer -ScriptBlock {
            $basePath = "C:\ProgramData\NetworkTests"
            $testFolders = Get-ChildItem -Path $basePath -Directory | 
                          Where-Object { $_.Name -match '^\d{8}_\d{6}$' } |
                          Sort-Object Name -Descending
            
            if (-not $testFolders) {
                return @{
                    Success = $false
                    Error = "No test results found"
                }
            }
            
            $latestFolder = $testFolders[0]
            $testPath = $latestFolder.FullName
            
            # Get all files except test.dat
            $files = Get-ChildItem -Path $testPath -File | 
                    Where-Object { $_.Name -ne 'test.dat' } |
                    ForEach-Object {
                        @{
                            Name = $_.Name
                            Content = Get-Content $_.FullName -Raw
                        }
                    }
            
            # Parse DiskSpd results if they exist
            $resultsFile = Join-Path $testPath "results.txt"
            $throughput = $iops = $null
            
            if (Test-Path $resultsFile) {
                $diskSpdResults = Get-Content $resultsFile
                $throughput = ($diskSpdResults | Select-String "total:\s+\d+" | Select-Object -Last 1) -replace '.*\s+(\d+\.\d+)\s+.*', '$1'
                $iops = ($diskSpdResults | Select-String "I/O per s" | Select-Object -Last 1) -replace '.*\s+(\d+\.\d+)\s+.*', '$1'
            }
            
            return @{
                Success = $true
                FolderName = $latestFolder.Name
                Files = $files
                Metrics = @{
                    Throughput = $throughput
                    IOPS = $iops
                }
            }
        }
        
        if ($remoteResults.Success) {
            # Save files
            foreach ($file in $remoteResults.Files) {
                $file.Content | Out-File -FilePath (Join-Path $computerPath $file.Name) -Force
            }
            
            # Add to results array
            $results += [PSCustomObject]@{
                ComputerName = $computer
                TestFolder = $remoteResults.FolderName
                Throughput = $remoteResults.Metrics.Throughput
                IOPS = $remoteResults.Metrics.IOPS
                Status = "Success"
            }
            
            Write-Host "Successfully collected results from $computer"
        }
        else {
            Write-Warning "Failed to collect results from $computer : $($remoteResults.Error)"
            $results += [PSCustomObject]@{
                ComputerName = $computer
                Status = "Failed"
                Error = $remoteResults.Error
            }
        }
    }
    catch {
        Write-Warning "Error processing $computer : $_"
        $results += [PSCustomObject]@{
            ComputerName = $computer
            Status = "Error"
            Error = $_.ToString()
        }
    }
}

# Save summary
$summaryPath = Join-Path $resultsPath "summary_results.csv"
$results | Export-Csv -Path $summaryPath -NoTypeInformation

Write-Host "`nResults collection completed"
Write-Host "Results directory: $resultsPath"
Write-Host "Summary file: $summaryPath"