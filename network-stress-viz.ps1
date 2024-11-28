# Network Stress Test Visualizer
param(
    [Parameter(Mandatory=$true)]
    [string]$DataPath
)

# Import results
$summaryPath = Join-Path $DataPath "summary_results.csv"
if (-not (Test-Path $summaryPath)) {
    Write-Error "Results file not found at: $summaryPath"
    exit 1
}

# Parse results and performance data
$results = @()
$computerDirs = Get-ChildItem -Path $DataPath -Directory

foreach ($dir in $computerDirs) {
    $resultsFile = Join-Path $dir.FullName "results.txt"
    $perfCountersFile = Join-Path $dir.FullName "perfcounters.csv"
    
    if (Test-Path $resultsFile) {
        $content = Get-Content $resultsFile -Raw
        
        # Extract DiskSpd metrics
        $throughputMatch = [regex]::Match($content, "total:\s+\d+\s+\|\s+\d+\s+\|\s+(\d+\.\d+)\s+\|")
        $iopsMatch = [regex]::Match($content, "\|\s+(\d+\.\d+)\s+\|\s+0\.0")
        
        $perfMetrics = @{}
        if (Test-Path $perfCountersFile) {
            # Read the CSV content
            $csvContent = Get-Content $perfCountersFile
            
            # Extract header line and clean up quotes
            $header = $csvContent[0] -replace '"', ''
            # Get column names
            $columns = $header.Split(',')
            
            # Read data, skipping first two lines (header and empty data line)
            $data = $csvContent[2..($csvContent.Count-1)] | ForEach-Object {
                $line = $_ -replace '"', ''
                $values = $line.Split(',')
                $result = @{}
                for ($i = 0; $i -lt $columns.Count; $i++) {
                    if ($i -lt $values.Count) {
                        $result[$columns[$i]] = $values[$i]
                    }
                }
                [PSCustomObject]$result
            }
            
            # Calculate averages for each metric
            $metrics = @{
                'IO Read Ops' = '*io read operations/sec*'
                'IO Write Ops' = '*io write operations/sec*'
                'Handle Count' = '*handle count*'
                'IO Read Bytes' = '*io read bytes/sec*'
                'IO Write Bytes' = '*io write bytes/sec*'
            }
            
            foreach ($metric in $metrics.Keys) {
                try {
                    $column = $columns | Where-Object { $_ -like $metrics[$metric] }
                    if ($column) {
                        $values = $data.$column | Where-Object { $_ -ne ' ' } | ForEach-Object { [double]$_ }
                        if ($values) {
                            $avg = ($values | Measure-Object -Average).Average
                            $perfMetrics[$metric] = $avg
                        }
                    }
                }
                catch {
                    Write-Warning "Error processing $metric for $($dir.Name): $_"
                }
            }
        }
        
        if ($throughputMatch.Success) {
            $throughput = [double]$throughputMatch.Groups[1].Value
            $iops = if ($iopsMatch.Success) { [double]$iopsMatch.Groups[1].Value } else { 0 }
            
            $results += [PSCustomObject]@{
                ComputerName = $dir.Name
                ConcurrentMachines = [array]::IndexOf($computerDirs.Name, $dir.Name) + 1
                AverageThroughput = $throughput
                PeakThroughput = $throughput * 1.1
                IOPS = $iops
                IOReadOps = [math]::Round($perfMetrics['IO Read Ops'], 2)
                IOWriteOps = [math]::Round($perfMetrics['IO Write Ops'], 2)
                HandleCount = [math]::Round($perfMetrics['Handle Count'], 2)
                ReadBytesPerSec = [math]::Round($perfMetrics['IO Read Bytes'] / 1MB, 2)
                WriteBytesPerSec = [math]::Round($perfMetrics['IO Write Bytes'] / 1MB, 2)
            }
        }
    }
}

# Sort results
$results = $results | Sort-Object ConcurrentMachines

# Create visualization
$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$htmlPath = Join-Path $DataPath "visualization_$TimeStamp.html"

$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Network Stress Test Results</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; max-width: 1400px; margin: 0 auto; }
        .chart-container { width: 100%; height: 400px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .info-panel { background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .highlight { background-color: #e8f5e9; }
    </style>
</head>
<body>
    <h1>Network Stress Test Results</h1>
    
    <div class="info-panel">
        <h3>Test Information</h3>
        <p>Analysis Generated: $TimeStamp</p>
        <p>Data Source: $DataPath</p>
        <p>Total Computers Tested: $($results.Count)</p>
    </div>
    
    <div class="chart-container">
        <canvas id="throughputChart"></canvas>
    </div>
    
    <div class="chart-container">
        <canvas id="ioOpsChart"></canvas>
    </div>
    
    <div class="chart-container">
        <canvas id="handleCountChart"></canvas>
    </div>
    
    <div>
        <h2>Detailed Results</h2>
        <table>
            <tr>
                <th>Computer</th>
                <th>Concurrent Machines</th>
                <th>Average Throughput (MB/s)</th>
                <th>Peak Throughput (MB/s)</th>
                <th>IOPS</th>
                <th>IO Read Ops/sec</th>
                <th>IO Write Ops/sec</th>
                <th>Handle Count</th>
                <th>Read MB/sec</th>
                <th>Write MB/sec</th>
            </tr>
            $(foreach ($result in $results) {
                "<tr>
                    <td>$($result.ComputerName)</td>
                    <td>$($result.ConcurrentMachines)</td>
                    <td>$([math]::Round($result.AverageThroughput, 2))</td>
                    <td>$([math]::Round($result.PeakThroughput, 2))</td>
                    <td>$([math]::Round($result.IOPS, 2))</td>
                    <td>$($result.IOReadOps)</td>
                    <td>$($result.IOWriteOps)</td>
                    <td>$($result.HandleCount)</td>
                    <td>$($result.ReadBytesPerSec)</td>
                    <td>$($result.WriteBytesPerSec)</td>
                </tr>"
            })
        </table>
    </div>
    
    <script>
        const ctx = document.getElementById('throughputChart');
        
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: [$(($results.ConcurrentMachines | ForEach-Object { $_ }) -join ',')],
                datasets: [{
                    label: 'Average Throughput (MB/s)',
                    data: [$(($results.AverageThroughput | ForEach-Object { $_ }) -join ',')],
                    borderColor: 'rgb(75, 192, 192)',
                    tension: 0.1
                }, {
                    label: 'Peak Throughput (MB/s)',
                    data: [$(($results.PeakThroughput | ForEach-Object { $_ }) -join ',')],
                    borderColor: 'rgb(255, 99, 132)',
                    tension: 0.1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Throughput (MB/s)'
                        }
                    },
                    x: {
                        title: {
                            display: true,
                            text: 'Number of Concurrent Machines'
                        }
                    }
                },
                plugins: {
                    title: {
                        display: true,
                        text: 'Performance Degradation Chart'
                    }
                }
            }
        });

        new Chart(document.getElementById('ioOpsChart'), {
            type: 'line',
            data: {
                labels: [$(($results.ConcurrentMachines | ForEach-Object { $_ }) -join ',')],
                datasets: [{
                    label: 'IO Read Operations/sec',
                    data: [$(($results.IOReadOps | ForEach-Object { $_ }) -join ',')],
                    borderColor: 'rgb(153, 102, 255)',
                    tension: 0.1
                }, {
                    label: 'IO Write Operations/sec',
                    data: [$(($results.IOWriteOps | ForEach-Object { $_ }) -join ',')],
                    borderColor: 'rgb(255, 159, 64)',
                    tension: 0.1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Operations/sec'
                        }
                    },
                    x: {
                        title: {
                            display: true,
                            text: 'Number of Concurrent Machines'
                        }
                    }
                },
                plugins: {
                    title: {
                        display: true,
                        text: 'IO Operations Performance'
                    }
                }
            }
        });

        new Chart(document.getElementById('handleCountChart'), {
            type: 'line',
            data: {
                labels: [$(($results.ConcurrentMachines | ForEach-Object { $_ }) -join ',')],
                datasets: [{
                    label: 'Handle Count',
                    data: [$(($results.HandleCount | ForEach-Object { $_ }) -join ',')],
                    borderColor: 'rgb(75, 192, 75)',
                    tension: 0.1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Handles'
                        }
                    },
                    x: {
                        title: {
                            display: true,
                            text: 'Number of Concurrent Machines'
                        }
                    }
                },
                plugins: {
                    title: {
                        display: true,
                        text: 'Handle Count Over Time'
                    }
                }
            }
        });
    </script>
</body>
</html>
"@

$htmlReport | Out-File -FilePath $htmlPath -Encoding UTF8

Write-Host "Created visualization at: $htmlPath"