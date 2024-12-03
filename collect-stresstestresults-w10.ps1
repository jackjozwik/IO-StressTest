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

# Read computer names
$excel = Import-Excel -Path $ExcelPath
$firstCol = $excel[0].PSObject.Properties.Name | Select-Object -First 1
$computers = $excel | Select-Object -ExpandProperty $firstCol | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$allResults = @()

foreach ($computer in $computers) {
    Write-Host "Collecting results from $computer..."
    
    try {
        # Get two most recent test folders
        $remoteResults = Invoke-Command -ComputerName $computer -ScriptBlock {
            $basePath = "C:\ProgramData\NetworkTests"
            $testFolders = Get-ChildItem -Path $basePath -Directory | 
                          Where-Object { $_.Name -match '^\d{8}_\d{6}$' } |
                          Sort-Object Name -Descending |
                          Select-Object -First 2
            
            if (-not $testFolders) {
                return @{
                    Success = $false
                    Error = "No test results found"
                }
            }
            
            $folderResults = @()
            foreach ($folder in $testFolders) {
                $testPath = $folder.FullName
                
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
                
                $folderResults += @{
                    FolderName = $folder.Name
                    Files = $files
                    Metrics = @{
                        Throughput = $throughput
                        IOPS = $iops
                    }
                }
            }
            
            return @{
                Success = $true
                Results = $folderResults
            }
        }
        
        if ($remoteResults.Success) {
            foreach ($testResult in $remoteResults.Results) {
                # Create separate timestamp directory for each test
                $resultsPath = Join-Path $OutputPath $testResult.FolderName
                New-Item -ItemType Directory -Force -Path $resultsPath | Out-Null
                
                # Create computer-specific directory
                $computerPath = Join-Path $resultsPath $computer
                New-Item -ItemType Directory -Force -Path $computerPath | Out-Null
                
                # Save files
                foreach ($file in $testResult.Files) {
                    $file.Content | Out-File -FilePath (Join-Path $computerPath $file.Name) -Force
                }
                
                # Add to results array
                $allResults += [PSCustomObject]@{
                    ComputerName = $computer
                    TestFolder = $testResult.FolderName
                    Throughput = $testResult.Metrics.Throughput
                    IOPS = $testResult.Metrics.IOPS
                    Status = "Success"
                }
                
                # Save individual test summary
                $summaryPath = Join-Path $resultsPath "summary_results.csv"
                $allResults | Where-Object TestFolder -eq $testResult.FolderName | 
                    Export-Csv -Path $summaryPath -NoTypeInformation
            }
            
            Write-Host "Successfully collected results from $computer"
        }
        else {
            Write-Warning "Failed to collect results from $computer : $($remoteResults.Error)"
            $allResults += [PSCustomObject]@{
                ComputerName = $computer
                Status = "Failed"
                Error = $remoteResults.Error
            }
        }
    }
    catch {
        Write-Warning "Error processing $computer : $_"
        $allResults += [PSCustomObject]@{
            ComputerName = $computer
            Status = "Error"
            Error = $_.ToString()
        }
    }
}

Write-Host "`nResults collection completed"