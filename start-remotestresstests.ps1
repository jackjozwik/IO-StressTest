# File: Start-NetworkStressTest.ps1
param(
    [Parameter(Mandatory = $true)]
    [string]$ExcelPath,
    [int]$BaselineDuration = 600,
    [int]$StaggerDelay = 10,
    [int]$FileSize = 8
)

# Import Excel module if needed
if (-not (Get-Module -Name ImportExcel)) {
    Install-Module -Name ImportExcel -Force -Scope CurrentUser
}

# Read computer names
$excel = Import-Excel -Path $ExcelPath
$firstCol = $excel[0].PSObject.Properties.Name | Select-Object -First 1
$computers = $excel | Select-Object -ExpandProperty $firstCol | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

# Calculate timing and create timestamp
$totalComputers = $computers.Count
$totalDelay = ($totalComputers - 1) * $StaggerDelay
$totalRuntime = $BaselineDuration + $totalDelay
$estimatedEnd = (Get-Date).AddSeconds($totalRuntime)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Show test configuration
Write-Host "Test Configuration:"
Write-Host "==================="
Write-Host "Number of computers: $totalComputers"
Write-Host "Test duration per computer: $($BaselineDuration/60) minutes"
Write-Host "Delay between computers: $StaggerDelay seconds"
Write-Host "Total estimated runtime: $($totalRuntime/60) minutes"
Write-Host "Estimated completion: $($estimatedEnd.ToString('MM/dd/yyyy HH:mm:ss'))"
Write-Host "Test file size: $FileSize GB"
Write-Host "Results will be saved in: C:\ProgramData\NetworkTests\$timestamp"
Write-Host ""

# Confirm before proceeding
$confirm = Read-Host "Proceed with test? (Y/N)"
if ($confirm -ne "Y") {
    Write-Host "Test cancelled."
    exit
}

# Start tests with staggered delays
foreach ($index in 0..($computers.Count - 1)) {
    $computer = $computers[$index]
    $startDelay = $index * $StaggerDelay
    
    Write-Host "Starting test on $computer (Computer $($index + 1) of $($computers.Count))"
    
    Start-Job -ScriptBlock {
        param($Computer, $Delay, $Duration, $Size, $TimeStamp)
        
        Start-Sleep -Seconds $Delay
        
        Invoke-Command -ComputerName $Computer -ScriptBlock {
            param($Duration, $Size, $TimeStamp)
            
            # Create test directory
            $testPath = "C:\ProgramData\NetworkTests\$TimeStamp"
            New-Item -ItemType Directory -Force -Path $testPath | Out-Null
            
            $diskspd = "C:\ProgramData\NetworkTools\diskspd.exe"
            $testFile = Join-Path $testPath "test.dat"
            $outputFile = Join-Path $testPath "results.txt"
            $perfCounterFile = Join-Path $testPath "perfcounters.csv"
            
            # Log start
            "Starting test at $(Get-Date)" | Out-File "$testPath\log.txt"

            # First start DiskSpd in background
            $diskspdProc = Start-Process -FilePath $diskspd -ArgumentList "-c${Size}G -d$Duration -r -t1 -b4K -L -o32 -W15 -D -Suw $testFile" -NoNewWindow -PassThru -RedirectStandardOutput $outputFile
            
            # Wait a moment for the process to fully start
            Start-Sleep -Seconds 5

            # Define performance counters (using specific process instance)
            $counters = @(
                "\Memory\Available MBytes",
                "\PhysicalDisk(_Total)\Disk Read Bytes/sec",
                "\PhysicalDisk(_Total)\Disk Write Bytes/sec"
            )
            
            # Add process-specific counters now that we have the PID
            $counters = @(
                "\Process(diskspd)\IO Read Operations/sec",
                "\Process(diskspd)\IO Write Operations/sec",
                "\Process(diskspd)\Handle Count",
                "\Process(diskspd)\IO Read Bytes/sec",
                "\Process(diskspd)\IO Write Bytes/sec",
                "\PhysicalDisk(_Total)\Disk Read Bytes/sec",
                "\PhysicalDisk(_Total)\Disk Write Bytes/sec"
            )
            $counters += $processCounters
            
            "Starting performance counter collection at $(Get-Date)" | Out-File "$testPath\log.txt" -Append
            
            # Collect counters for the duration
            $counterData = Get-Counter -Counter $counters -SampleInterval 1 -MaxSamples $Duration
            $counterData | Export-Counter -FileFormat CSV -Path $perfCounterFile -Force

            
            # Wait for DiskSpd to finish if it hasn't already
            $diskspdProc | Wait-Process
            
            # Parse performance counter data
            if (Test-Path $perfCounterFile) {
                $countersCSV = Import-Csv $perfCounterFile
                
                # Calculate averages (using try-catch for each metric)
                $summary = @{}
                
                foreach ($metric in @(
                        'IO Read Operations/sec',
                        'IO Write Operations/sec',
                        'Handle Count',
                        'Working Set',
                        '% Processor Time',
                        'Available MBytes',
                        'Disk Read Bytes/sec',
                        'Disk Write Bytes/sec'
                    )) {
                    try {
                        $column = $countersCSV.PSObject.Properties | 
                        Where-Object { $_.Name -like "*$metric" } |
                        Select-Object -First 1 -ExpandProperty Name
                        
                        if ($column) {
                            $avg = ($countersCSV.$column | Measure-Object -Average).Average
                            $summary["Avg$($metric -replace '[^a-zA-Z0-9]', '')"] = $avg
                        }
                    }
                    catch {
                        "Error processing $metric : $_" | Out-File "$testPath\log.txt" -Append
                    }
                }
                
                # Save summary
                $summary | ConvertTo-Json | Out-File -FilePath "$testPath\perf_summary.json"
            }
            
            # Log completion
            "Test completed at $(Get-Date)" | Out-File "$testPath\log.txt" -Append
            
        } -ArgumentList $Duration, $Size, $TimeStamp
        
    } -ArgumentList $computer, $startDelay, $BaselineDuration, $FileSize, $timestamp
}

Write-Host "`nAll tests started. Waiting for completion..."
Write-Host "Monitoring jobs..."

# Wait for all jobs and show results
Get-Job | Wait-Job | Receive-Job
Get-Job | Remove-Job

Write-Host "`nTests completed!"
Write-Host "Results are in C:\ProgramData\NetworkTests\$timestamp on each computer"
Write-Host "Use Collect-StressTestResults.ps1 to gather results"