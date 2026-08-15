param($ScriptPath)

$proc = Start-Process powershell -ArgumentList "-File `"$ScriptPath`"" -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\lucebox-test-out.txt" -RedirectStandardError "$env:TEMP\lucebox-test-err.txt"

# Wait for "[server] listening" in output, up to 60s
$deadline = (Get-Date).AddSeconds(60)
$ready = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    if (Test-Path "$env:TEMP\lucebox-test-out.txt") {
        $content = Get-Content "$env:TEMP\lucebox-test-out.txt" -Raw
        if ($content -match '\[server\] listening') {
            $ready = $true
            break
        }
    }
    if ($proc.HasExited) {
        Write-Host "Process exited early (code $($proc.ExitCode))"
        Get-Content "$env:TEMP\lucebox-test-err.txt" -Tail 20
        Get-Content "$env:TEMP\lucebox-test-out.txt" -Tail 20
        exit 1
    }
}

if (-not $ready) {
    Write-Host "TIMEOUT: server didn't reach listening state"
    $proc.Kill()
    Get-Content "$env:TEMP\lucebox-test-err.txt" -Tail 20
    exit 1
}

Write-Host "Server listening!"
Write-Host "--- /v1/models ---"
try { Invoke-RestMethod -Uri "http://$($configHost):$($configPort)/v1/models" -TimeoutSec 5 } catch { Write-Host "ERROR: $_" }

Write-Host "--- tiny chat ---"
$body = @{model="localmodel"; messages=@(@{role="user"; content="hi"}; @{role="assistant"; content="hello"}); max_tokens=1; stream=$false} | ConvertTo-Json -Depth 4 -Compress
try { $r = Invoke-RestMethod -Uri "http://$($configHost):$($configPort)/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 30; Write-Host "OK: $($r.choices[0].message.content)" } catch { Write-Host "CHAT ERROR: $_" }

$proc.Kill()
Write-Host "Done."
