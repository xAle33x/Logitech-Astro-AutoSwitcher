# =========================================================
# Logitech G HUB Battery Key Finder Helper
# =========================================================

$GhubDir = "$env:LocalAppData\LGHUB"
$Files = @("settings.db", "settings.db-wal")

Write-Host "Scanning G HUB databases for battery keys..." -ForegroundColor Yellow

foreach ($file in $Files) {
    $Path = Join-Path $GhubDir $file
    if (Test-Path $Path) {
        
        # Open file in safe read-only mode (prevents crashing G HUB)
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.BinaryReader($fs)
        $bytes = $reader.ReadBytes($fs.Length)
        $reader.Close(); $fs.Close()
        
        $RawData = [System.Text.Encoding]::UTF8.GetString($bytes)
        
        # Search for ANY string starting with "battery/"
        $RegexPattern = '"(battery/[^"]+)"'
        $Matches = [regex]::Matches($RawData, $RegexPattern)
        
        if ($Matches.Count -gt 0) {
            Write-Host "`n--- Found in $file ---" -ForegroundColor Cyan
            $Matches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        }
    }
}
Write-Host "-----------------------------------------------`n" -ForegroundColor Cyan
Write-Host "Copy the key that looks like 'battery/YOUR_HEADSET/percentage' and paste it into the main AutoSwitch script." -ForegroundColor Green
Write-Host "`n"
Read-Host "Press Enter to exit..."
