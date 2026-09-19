<#
.SYNOPSIS
  Diagnostica mirata: dove vive oggi il flag di carica dell'A50.
  ESEGUIRE DUE VOLTE: (1) con headset SULLA BASE, (2) con headset TOLTO dalla base.
  Confrontare i due output.
#>

$GhubDir = "$env:LocalAppData\LGHUB"

function Read-Raw {
    param($Path)
    try {
        $f = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $r = New-Object System.IO.BinaryReader($f)
        $b = $r.ReadBytes($f.Length); $r.Close(); $f.Close()
        return [System.Text.Encoding]::UTF8.GetString($b)
    } catch { return $null }
}

function Get-JsonBlock {
    param($Raw, $From)
    $open = $Raw.IndexOf('{', $From)
    if ($open -lt 0) { return $null }
    $depth = 0
    $max = [Math]::Min($Raw.Length, $open + 3000)
    for ($i = $open; $i -lt $max; $i++) {
        if ($Raw[$i] -eq '{') { $depth++ }
        elseif ($Raw[$i] -eq '}') { $depth--; if ($depth -eq 0) { return $Raw.Substring($open, $i-$open+1) } }
    }
    return $null
}

$Files = @("settings.db", "settings.db-wal") | ForEach-Object { Join-Path $GhubDir $_ } | Where-Object { Test-Path $_ }

Write-Host "`n=== A) BLOCCO COMPLETO battery/a50/percentage (TUTTE le occorrenze) ===" -ForegroundColor Cyan
foreach ($path in $Files) {
    $raw = Read-Raw $path; if (-not $raw) { continue }
    $ms = [regex]::Matches($raw, '"battery/a50/percentage"')
    Write-Host "--- $(Split-Path $path -Leaf) : $($ms.Count) occorrenze ---" -ForegroundColor Yellow
    foreach ($m in $ms) {
        $block = Get-JsonBlock $raw $m.Index
        Write-Host "  offset $($m.Index): $($block -replace '\s+',' ')" -ForegroundColor White
    }
}

Write-Host "`n=== B) CHI CONTIENE 'isCharging'? (400 char PRIMA di ogni occorrenza) ===" -ForegroundColor Cyan
foreach ($path in $Files) {
    $raw = Read-Raw $path; if (-not $raw) { continue }
    $ms = [regex]::Matches($raw, '"isCharging"\s*:\s*(true|false)')
    Write-Host "--- $(Split-Path $path -Leaf) : $($ms.Count) occorrenze ---" -ForegroundColor Yellow
    foreach ($m in $ms) {
        $start = [Math]::Max(0, $m.Index - 400)
        $ctx = $raw.Substring($start, $m.Index - $start + $m.Length)
        # ultima chiave "xxx": { che precede -> e' il proprietario
        $owners = [regex]::Matches($ctx, '"([a-zA-Z0-9_/\-]+)"\s*:\s*\{')
        $owner = if ($owners.Count) { $owners[$owners.Count-1].Groups[1].Value } else { "???" }
        Write-Host "  offset $($m.Index) | valore: $($m.Groups[1].Value) | contenitore probabile: $owner" -ForegroundColor Green
        Write-Host "     ctx: ...$(($ctx.Substring([Math]::Max(0,$ctx.Length-220))) -replace '\s+',' ')" -ForegroundColor DarkGray
    }
}

Write-Host "`n=== C) ALTRI CAMPI CHE POTREBBERO INDICARE LA CARICA ===" -ForegroundColor Cyan
foreach ($path in $Files) {
    $raw = Read-Raw $path; if (-not $raw) { continue }
    $pats = @('"charging[A-Za-z]*"\s*:\s*[^,}]+', '"[a-zA-Z]*[Dd]ocked"\s*:\s*[^,}]+', '"powerState"\s*:\s*"[^"]*"', '"level"\s*:\s*"[^"]*"', '"onBase"\s*:\s*[^,}]+')
    foreach ($p in $pats) {
        $h = [regex]::Matches($raw, $p) | ForEach-Object { $_.Value -replace '\s+',' ' } | Select-Object -Unique
        if ($h) { Write-Host "[$(Split-Path $path -Leaf)] $($h -join '  |  ')" -ForegroundColor Green }
    }
}

Write-Host "`n=== D) STATO ATTUALE HEADSET (dichiaralo tu) ===" -ForegroundColor Cyan
Write-Host "Ricorda di annotare: in questa esecuzione l'headset era SULLA BASE o TOLTO?" -ForegroundColor Yellow
