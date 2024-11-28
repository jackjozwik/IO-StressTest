# Deploy monitoring tools to remote machines
param(
    [string]$ExcelPath = "C:\Path\To\Your\Computers.xlsx",
    [string]$ToolsSharePath = "\\caisi\Home\jozwikch\tools",
	[string]$LocalToolsPath = "C:\ProgramData\NetworkTools"  

)

# Create a temporary staging directory
$stagingPath = Join-Path $env:TEMP "ToolsStaging"
New-Item -ItemType Directory -Force -Path $stagingPath | Out-Null

Write-Host "Created staging directory at $stagingPath"

# Copy tools to staging
$tools = @(
    "procexp.exe",
    "procmon.exe",
    "diskspd.exe"
)

foreach ($tool in $tools) {
    $sourcePath = Join-Path $ToolsSharePath $tool
    $stagingToolPath = Join-Path $stagingPath $tool
    Copy-Item -Path $sourcePath -Destination $stagingToolPath -Force
    Write-Host "Copied $tool to staging"
}

function Deploy-Tools {
    param(
        [string]$ComputerName,
        [string]$StagingPath,
        [string]$DestPath
    )
    
    Write-Host "Deploying to $ComputerName..."
    
    try {
        # Create session for file transfer
        $session = New-PSSession -ComputerName $ComputerName
        
        # Ensure destination directory exists
        Invoke-Command -Session $session -ScriptBlock {
            param($path)
            if (-not (Test-Path $path)) {
                New-Item -ItemType Directory -Force -Path $path | Out-Null
            }
        } -ArgumentList $DestPath
        
        # Copy each file using the session
        foreach ($tool in $tools) {
            $sourceFile = Join-Path $StagingPath $tool
            $destFile = Join-Path $DestPath $tool
            
            Write-Host "Copying $tool to $ComputerName..."
            Copy-Item -Path $sourceFile -Destination $destFile -ToSession $session -Force
        }
        
        Remove-PSSession $session
        return @{
            ComputerName = $ComputerName
            Success = $true
            Message = "Deployment successful"
        }
    }
    catch {
        if ($session) { Remove-PSSession $session }
        Write-Warning "Failed to deploy to $ComputerName : $_"
        return @{
            ComputerName = $ComputerName
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

# Read computer names from Excel
$excel = Import-Excel -Path $ExcelPath
if ($excel[0].PSObject.Properties.Name -contains "Column1") {
    $computers = $excel | Select-Object -ExpandProperty Column1
} else {
    $firstColumnName = $excel[0].PSObject.Properties.Name | Select-Object -First 1
    $computers = $excel | Select-Object -ExpandProperty $firstColumnName
}

# Filter out empty values
$computers = $computers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }

Write-Host "Found $($computers.Count) computers in Excel file"

# Deploy to all computers
$results = @()
foreach ($computer in $computers) {
    $result = Deploy-Tools -ComputerName $computer -StagingPath $stagingPath -DestPath $LocalToolsPath
    $results += $result
}

# Clean up staging directory
Remove-Item -Path $stagingPath -Recurse -Force
Write-Host "Cleaned up staging directory"

# Generate report
$reportPath = Join-Path $ToolsSharePath "deployment_report.csv"
$results | Export-Csv -Path $reportPath -NoTypeInformation

# Display summary
$successful = ($results | Where-Object Success).Count
$failed = ($results | Where-Object { -not $_.Success }).Count
Write-Host "`nDeployment Summary:"
Write-Host "Successful: $successful"
Write-Host "Failed: $failed"