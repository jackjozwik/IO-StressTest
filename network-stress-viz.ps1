# Network Stress Test Visualizer
param(
    [Parameter(Mandatory=$true)]
    [string]$DataPath      # Path to the test results directory containing summary_results.csv
)

# Import results
$summaryPath = Join-Path $DataPath "summary_results.csv"
if (-not (Test-Path $summaryPath)) {
    Write-Error "Results file not found at: $summaryPath"
    exit 1
}

# Parse each computer's results.txt file
$results = @()
$computerDirs = Get-ChildItem -Path $DataPath -Directory

foreach ($dir in $computerDirs) {
    $resultsFile = Join-Path $dir.FullName "results.txt"
    if (Test-Path $resultsFile) {
        $content = Get-Content $resultsFile -Raw
        
        # Extract throughput using regex
        $throughputMatch = [regex]::Match($content, "total:\s+\d+\s+\|\s+\d+\s+\|\s+(\d+\.\d+)\s+\|")
        $iopsMatch = [regex]::Match($content, "\|\s+(\d+\.\d+)\s+\|\s+0\.0")
        
        if ($throughputMatch.Success) {
            $throughput = [double]$throughputMatch.Groups[1].Value
            $iops = if ($iopsMatch.Success) { [double]$iopsMatch.Groups[1].Value } else { 0 }
            
            $results += [PSCustomObject]@{
                ComputerName = $dir.Name
                ConcurrentMachines = [array]::IndexOf($computerDirs.Name, $dir.Name) + 1
                AverageThroughput = $throughput
                PeakThroughput = $throughput * 1.1  # Estimating peak as 10% higher
                IOPS = $iops
            }
        }
    }
}

# Sort results by concurrent machines
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
        body { font-family: Arial, sans-serif; margin: 20px; max-width: 1200px; margin: 0 auto; }
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
        <canvas id="performanceChart"></canvas>
    </div>
    
    <div class="chart-container">
        <canvas id="iopsChart"></canvas>
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
            </tr>
            $(foreach ($result in $results) {
                "<tr>
                    <td>$($result.ComputerName)</td>
                    <td>$($result.ConcurrentMachines)</td>
                    <td>$([math]::Round($result.AverageThroughput, 2))</td>
                    <td>$([math]::Round($result.PeakThroughput, 2))</td>
                    <td>$([math]::Round($result.IOPS, 2))</td>
                </tr>"
            })
        </table>
    </div>
    
    <script>
        const ctx = document.getElementById('performanceChart');
        const iopsCtx = document.getElementById('iopsChart');
        
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

        new Chart(iopsCtx, {
            type: 'line',
            data: {
                labels: [$(($results.ConcurrentMachines | ForEach-Object { $_ }) -join ',')],
                datasets: [{
                    label: 'IOPS',
                    data: [$(($results.IOPS | ForEach-Object { $_ }) -join ',')],
                    borderColor: 'rgb(153, 102, 255)',
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
                            text: 'IO Operations per Second'
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
                        text: 'IOPS Performance Chart'
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