# File: Start-NetworkStressTest.ps1
param(
    [Parameter(Mandatory=$true)]
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
foreach ($index in 0..($computers.Count-1)) {
    $computer = $computers[$index]
    $startDelay = $index * $StaggerDelay
    
    Write-Host "Starting test on $computer (delay: $startDelay seconds)"
    
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
            
            # Log start
            "Starting test at $(Get-Date)" | Out-File "$testPath\log.txt"
            
            # Run DiskSpd with the working command structure
            $cmd = "& '$diskspd' -c${Size}G -d$Duration -r -t1 -b4K -L -o32 -W15 -D -Suw '$testFile' > '$outputFile' 2>&1"
            "Running command: $cmd" | Out-File "$testPath\log.txt" -Append
            
            Invoke-Expression $cmd
            
            # Log completion and verify results
            "Test completed at $(Get-Date)" | Out-File "$testPath\log.txt" -Append
            
            if (Test-Path $outputFile) {
                $content = Get-Content $outputFile
                "Results file has $($content.Count) lines" | Out-File "$testPath\log.txt" -Append
            } else {
                "ERROR: Results file was not created" | Out-File "$testPath\log.txt" -Append
            }
            
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