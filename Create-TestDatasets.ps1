$Root = "C:\LabTest"

Write-Host ""
Write-Host "========================================"
Write-Host "       TEST DATASET GENERATOR"
Write-Host "========================================"
Write-Host ""

# Remove old datasets
if (Test-Path $Root) {
    Write-Host "Removing previous test datasets..."
    Remove-Item $Root -Recurse -Force
}

New-Item -Path $Root -ItemType Directory -Force | Out-Null

function New-TestFiles {
    param(
        [string]$Name,
        [int]$Count,
        [int]$SizeMiB
    )

    $Folder = Join-Path $Root $Name
    New-Item -Path $Folder -ItemType Directory -Force | Out-Null

    Write-Host ""
    Write-Host "Creating dataset: $Name"
    Write-Host "Files       : $Count"
    Write-Host "File size   : $SizeMiB MiB"
    Write-Host "Total size  : $([math]::Round(($Count * $SizeMiB), 2)) MiB"
    Write-Host ""

    $BufferSize = 1MB
    $Buffer = New-Object byte[] $BufferSize

    # Fill buffer with deterministic non-zero data
    for ($i = 0; $i -lt $Buffer.Length; $i++) {
        $Buffer[$i] = [byte](($i * 31) % 256)
    }

    for ($n = 1; $n -le $Count; $n++) {

        $FileName = "{0}_{1:D4}.bin" -f $Name, $n
        $FilePath = Join-Path $Folder $FileName

        $Stream = [System.IO.File]::Open(
            $FilePath,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )

        try {
            for ($m = 0; $m -lt $SizeMiB; $m++) {
                $Stream.Write($Buffer, 0, $Buffer.Length)
            }
        }
        finally {
            $Stream.Close()
            $Stream.Dispose()
        }

        if ($n % 100 -eq 0 -or $n -eq $Count) {
            Write-Host "Created $n / $Count"
        }
    }
}

# Small: 1000 x 1 MiB
New-TestFiles -Name "Small" -Count 1000 -SizeMiB 1

# Medium: 100 x 10 MiB
New-TestFiles -Name "Medium" -Count 100 -SizeMiB 10

# Large: 10 x 100 MiB
New-TestFiles -Name "Large" -Count 10 -SizeMiB 100

Write-Host ""
Write-Host "========================================"
Write-Host "       DATASET VERIFICATION"
Write-Host "========================================"
Write-Host ""

foreach ($Name in @("Small", "Medium", "Large")) {

    $Folder = Join-Path $Root $Name
    $Files = Get-ChildItem $Folder -File
    $TotalBytes = ($Files | Measure-Object Length -Sum).Sum

    Write-Host "$Name"
    Write-Host "  Files : $($Files.Count)"
    Write-Host "  Size  : $([math]::Round($TotalBytes / 1MB, 2)) MiB"
    Write-Host ""
}

Write-Host "Dataset generation completed."
Write-Host ""
