$ErrorActionPreference = 'Stop'
$script = 'C:\Users\brock\Documents\github\beellama\run\Qwopus3.6-27B-Coder-Q4_K_M-dflash-lucebox.ps1'

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'powershell.exe'
$psi.Arguments = "-NoProfile -File `"$script`""
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$deadline = (Get-Date).AddSeconds(45)
$listening = $false

while ((Get-Date) -lt $deadline -and !$proc.HasExited) {
    Start-Sleep -Milliseconds 500
    $line = $proc.StandardOutput.ReadLine()
    if ($line) { Write-Host $line }
    if ($line -match 'listening') { $listening = $true; break }
}

if ($listening) {
    Write-Host "SERVER READY - testing..."
    Start-Sleep 2
    try {
        $r = Invoke-RestMethod -Uri 'http://0.0.0.0:8082/v1/models' -TimeoutSec 5
        Write-Host "MODELS: $($r | ConvertTo-Json -Depth 2)"
    } catch { Write-Host "MODELS ERROR: $_" }
    try {
        $body = '{"model":"localmodel","messages":[{"role":"user","content":"hi"}],"max_tokens":1,"stream":false}'
        $r = Invoke-RestMethod -Uri 'http://0.0.0.0:8082/v1/chat/completions' -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 30
        Write-Host "CHAT OK: $($r.choices[0].message.content)"
    } catch { Write-Host "CHAT ERROR: $_" }
} else {
    Write-Host "SERVER DID NOT START"
    $err = $proc.StandardError.ReadToEnd()
    if ($err) { Write-Host "STDERR: $err" }
}

if (!$proc.HasExited) { $proc.Kill() }
