# Start Argon with safeguard - only 1 instance allowed

$argonProcesses = Get-Process -Name argon -ErrorAction SilentlyContinue

if ($argonProcesses) {
    Write-Host "❌ Argon is already running (PID: $($argonProcesses.Id))"
    Write-Host "   Studio is connected to: localhost:8000"
    Write-Host "   Do NOT start another instance."
    exit
}

Write-Host "✅ Starting Argon..."
cd C:\pvp_game
argon serve
