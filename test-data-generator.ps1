# Simple Test Data Generator for Network Stress Testing
param(
    [string]$OutputPath = "M:\diskspd",
    [int]$NumberOfComputers = 3
)

# Import required module
if (-not (Get-Module -Name ImportExcel)) {
    Install-Module -Name ImportExcel -Force -Scope CurrentUser
}

function New-TestExcelFile {
    param([string]$Path)
    
    $computers = @(
        "TEST-PC-001",
        "TEST-PC-002",
        "TEST-PC-003"
    ) | ForEach-Object { [PSCustomObject]@{ ComputerName = $_ } }
    
    $excelPath = Join-Path $Path "test_computers.xlsx"
    $computers | Export-Excel -Path $excelPath -WorksheetName "Computers" -AutoSize
    return $excelPath
}

function New-TestData {
    param([string]$Path)
    
    $TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $TestResultPath = Join-Path $Path "TestResults_$TimeStamp"
    New-Item -ItemType Directory -Force -Path $TestResultPath | Out-Null
    
    # Generate test data
    $summaryResults = @(
        [PSCustomObject]@{
            ComputerName = "TEST-PC-001"
            StartTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            EndTime = (Get-Date).AddMinutes(5).ToString('yyyy-MM-dd HH:mm:ss')
            AverageThroughput = 950
            PeakThroughput = 975
            ConcurrentMachines = 1
        },
        [PSCustomObject]@{
            ComputerName = "TEST-PC-002"
            StartTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            EndTime = (Get-Date).AddMinutes(5).ToString('yyyy-MM-dd HH:mm:ss')
            AverageThroughput = 900
            PeakThroughput = 925
            ConcurrentMachines = 2
        },
        [PSCustomObject]@{
            ComputerName = "TEST-PC-003"
            StartTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            EndTime = (Get-Date).AddMinutes(5).ToString('yyyy-MM-dd HH:mm:ss')
            AverageThroughput = 850
            PeakThroughput = 875
            ConcurrentMachines = 3
        }
    )
    
    # Save CSV data
    $summaryResults | Export-Csv -Path (Join-Path $TestResultPath "summary_results.csv") -NoTypeInformation
    
    # Create HTML report
    $htmlPath = Join-Path $TestResultPath "test_results.html"
    
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Test Data: Network Stress Test Results</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; max-width: 1200px; margin: 0 auto; }
        .chart-container { width: 100%; height: 400px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .info-panel { background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Test Data: Network Stress Test Results</h1>
    
    <div class="info-panel">
        <h3>Test Information</h3>
        <p>Generated: $TimeStamp</p>
        <p>This is synthetic test data for visualization testing</p>
    </div>
    
    <div class="chart-container">
        <canvas id="performanceChart"></canvas>
    </div>
    
    <div>
        <h2>Detailed Results</h2>
        <table>
            <tr>
                <th>Computer</th>
                <th>Concurrent Machines</th>
                <th>Average Throughput (MB/s)</th>
                <th>Peak Throughput (MB/s)</th>
            </tr>
            $(foreach ($result in $summaryResults) {
                "<tr>
                    <td>$($result.ComputerName)</td>
                    <td>$($result.ConcurrentMachines)</td>
                    <td>$([math]::Round($result.AverageThroughput, 2))</td>
                    <td>$([math]::Round($result.PeakThroughput, 2))</td>
                </tr>"
            })
        </table>
    </div>
    
    <script>
        const ctx = document.getElementById('performanceChart');
        
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: [1, 2, 3],
                datasets: [{
                    label: 'Average Throughput (MB/s)',
                    data: [950, 900, 850],
                    borderColor: 'rgb(75, 192, 192)',
                    tension: 0.1
                }, {
                    label: 'Peak Throughput (MB/s)',
                    data: [975, 925, 875],
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
    </script>
</body>
</html>
"@
    
    $htmlReport | Out-File -FilePath $htmlPath -Encoding UTF8
    
    Write-Host "Generated test data and report at: $TestResultPath"
    Write-Host "Summary data: $(Join-Path $TestResultPath 'summary_results.csv')"
    Write-Host "HTML Report: $htmlPath"
    
    return $TestResultPath
}

# Main execution
try {
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    }
    
    # Generate test environment
    $excelPath = New-TestExcelFile -Path $OutputPath
    $testDataPath = New-TestData -Path $OutputPath
    
    Write-Host "`nTest environment created successfully!"
    Write-Host "Excel file: $excelPath"
    Write-Host "Test data: $testDataPath"
} catch {
    Write-Error "Error generating test data: $_"
}