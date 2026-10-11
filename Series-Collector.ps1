param(
    [string]$SignalFolder = "\\192.168.50.10\LabShare\Signals",
    [int]$MaxWait = 120
)

$Counters = @(
    '\Process(MsMpEng)\% Processor Time',
    '\Processor(_Total)\% Processor Time',
    '\PhysicalDisk(_Total)\Disk Bytes/sec',
    '\PhysicalDisk(_Total)\Avg. Disk Queue Length'
)

$StartSignal = Join-Path $SignalFolder "START.signal"
$DoneSignal  = Join-Path $SignalFolder "DONE.signal"

Remove-Item $StartSignal -Force -ErrorAction SilentlyContinue
Remove-Item $DoneSignal -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "========================================"
Write-Host " SERIES PERFORMANCE COLLECTOR"
Write-Host "========================================"
Write-Host "Waiting for test runs..."
Write-Host ""

while ($true) {

    Remove-Item $StartSignal -Force -ErrorAction SilentlyContinue
    Remove-Item $DoneSignal -Force -ErrorAction SilentlyContinue

    $Waited = 0

    while (-not (Test-Path $StartSignal)) {
        Start-Sleep -Milliseconds 100
        $Waited += 0.1

        if ($Waited -ge $MaxWait) {
            Write-Host "Waiting..."
            $Waited = 0
        }
    }

    Start-Sleep -Milliseconds 200

    Write-Host "START detected. Collecting..."

    $Samples = @()

    while (-not (Test-Path $DoneSignal)) {

        $Sample = Get-Counter -Counter $Counters

        foreach ($Counter in $Sample.CounterSamples) {
            $Samples += [PSCustomObject]@{
                Timestamp = $Counter.Timestamp
                Counter   = $Counter.Path
                Value     = [double]$Counter.CookedValue
            }
        }

        Start-Sleep -Milliseconds 500
    }

    Write-Host "DONE detected."

    $Summary = @()

    foreach ($Group in ($Samples | Group-Object Counter)) {

        $Values = $Group.Group.Value |
            ForEach-Object { [double]$_ }

        $Summary += [PSCustomObject]@{
            Counter = $Group.Name
            Average = [math]::Round(
                (($Values | Measure-Object -Average).Average), 3
            )
            Maximum = [math]::Round(
                (($Values | Measure-Object -Maximum).Maximum), 3
            )
        }
    }

    $Summary |
        Export-Csv "\\192.168.50.10\LabShare\Signals\Last-Performance.csv" `
        -NoTypeInformation `
        -Encoding UTF8

    Write-Host "Performance summary saved."
    Write-Host "Waiting for next run..."
}
