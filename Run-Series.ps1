param(
    [string]$Dataset = "Medium",
    [string]$Scenario = "Baseline",
    [int]$Runs = 20
)

$Source = "C:\LabTest\$Dataset"
$SignalFolder = "\\192.168.50.10\LabShare\Signals"
$BaseDestination = "\\192.168.50.10\LabShare\Runs\$Scenario\$Dataset"

$StartSignal = Join-Path $SignalFolder "START.signal"
$DoneSignal  = Join-Path $SignalFolder "DONE.signal"
$PerformanceFile = Join-Path $SignalFolder "Last-Performance.csv"

$Output = "C:\Lab-Experiment-$Scenario-$Dataset.csv"

if (-not (Test-Path $Source)) {
    throw "Dataset not found: $Source"
}

if (-not (Test-Path $SignalFolder)) {
    throw "Signal folder unavailable."
}

if (Test-Path $Output) {
    Remove-Item $Output -Force
}

New-Item $BaseDestination -ItemType Directory -Force | Out-Null

$Files = Get-ChildItem $Source -File
$TotalBytes = ($Files | Measure-Object Length -Sum).Sum
$TotalMiB = $TotalBytes / 1MB

$AllResults = @()

Write-Host ""
Write-Host "========================================"
Write-Host " EXPERIMENTAL SERIES"
Write-Host "========================================"
Write-Host "Scenario : $Scenario"
Write-Host "Dataset  : $Dataset"
Write-Host "Runs     : $Runs"
Write-Host "Files    : $($Files.Count)"
Write-Host "Data     : $([math]::Round($TotalMiB,2)) MiB"
Write-Host "========================================"
Write-Host ""

for ($Run = 1; $Run -le $Runs; $Run++) {

    Write-Host ""
    Write-Host "----------------------------------------"
    Write-Host "RUN $Run / $Runs"
    Write-Host "----------------------------------------"

    $Destination = Join-Path $BaseDestination "Run_$Run"

    if (Test-Path $Destination) {
        Remove-Item $Destination -Recurse -Force
    }

    New-Item $Destination -ItemType Directory -Force | Out-Null

    Remove-Item $StartSignal -Force -ErrorAction SilentlyContinue
    Remove-Item $DoneSignal -Force -ErrorAction SilentlyContinue
    Remove-Item $PerformanceFile -Force -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2

    # Tell SRV to start monitoring
    New-Item $StartSignal -ItemType File -Force | Out-Null

    Start-Sleep -Milliseconds 500

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($File in $Files) {

        Copy-Item `
            -LiteralPath $File.FullName `
            -Destination (Join-Path $Destination $File.Name) `
            -Force
    }

    $Stopwatch.Stop()

    $Seconds = $Stopwatch.Elapsed.TotalSeconds
    $Throughput = $TotalMiB / $Seconds

    # Tell SRV to stop monitoring
    New-Item $DoneSignal -ItemType File -Force | Out-Null

    # Wait for performance summary
    $Waited = 0

    while (-not (Test-Path $PerformanceFile)) {
        Start-Sleep -Milliseconds 200
        $Waited += 0.2

        if ($Waited -ge 30) {
            Write-Warning "Performance summary timeout."
            break
        }
    }

    $MsMpEngAvg = $null
    $MsMpEngMax = $null
    $CPUAvg = $null
    $CPUMax = $null
    $DiskAvg = $null
    $DiskMax = $null
    $QueueAvg = $null
    $QueueMax = $null

    if (Test-Path $PerformanceFile) {

        $Performance = Import-Csv $PerformanceFile

        foreach ($Row in $Performance) {

            $ValueAvg = [double]$Row.Average
            $ValueMax = [double]$Row.Maximum

            if ($Row.Counter -like "*MsMpEng*% processor time*") {
                $MsMpEngAvg = $ValueAvg
                $MsMpEngMax = $ValueMax
            }
            elseif ($Row.Counter -like "*processor(_total)*% processor time*") {
                $CPUAvg = $ValueAvg
                $CPUMax = $ValueMax
            }
            elseif ($Row.Counter -like "*physicaldisk(_total)*disk bytes/sec*") {
                $DiskAvg = $ValueAvg
                $DiskMax = $ValueMax
            }
            elseif ($Row.Counter -like "*avg. disk queue length*") {
                $QueueAvg = $ValueAvg
                $QueueMax = $ValueMax
            }
        }
    }

    $Result = [PSCustomObject]@{
        Scenario          = $Scenario
        Dataset           = $Dataset
        Run               = $Run
        Files             = $Files.Count
        MiB               = [math]::Round($TotalMiB,2)
        Time_s            = [math]::Round($Seconds,3)
        MiB_s             = [math]::Round($Throughput,2)
        MsMpEng_CPU_Avg   = $MsMpEngAvg
        MsMpEng_CPU_Max   = $MsMpEngMax
        CPU_Avg           = $CPUAvg
        CPU_Max           = $CPUMax
        Disk_Avg          = $DiskAvg
        Disk_Max          = $DiskMax
        Queue_Avg         = $QueueAvg
        Queue_Max         = $QueueMax
    }

    $AllResults += $Result

    $AllResults |
        Export-Csv $Output -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host "Throughput : $([math]::Round($Throughput,2)) MiB/s"
    Write-Host "MsMpEng    : $MsMpEngAvg %"
    Write-Host "CPU        : $CPUAvg %"
    Write-Host "Disk       : $DiskAvg bytes/s"
    Write-Host "Queue      : $QueueAvg"
    Write-Host ""

    # Cleanup destination after measurement
    Remove-Item $Destination -Recurse -Force

    if ($Run -lt $Runs) {
        Write-Host "Cooling down for 3 seconds..."
        Start-Sleep -Seconds 3
    }
}

Write-Host ""
Write-Host "========================================"
Write-Host " SERIES COMPLETE"
Write-Host "========================================"
Write-Host "Output: $Output"
Write-Host ""

$AllResults |
    Format-Table Run,MiB_s,MsMpEng_CPU_Avg,CPU_Avg,Disk_Avg,Queue_Avg `
    -AutoSize
