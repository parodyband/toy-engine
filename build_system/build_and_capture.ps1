Param(
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

# 1) Build the game
Write-Host "Building..."
& "$WorkspaceRoot\build_game.exe"

# 2) Launch the game and capture its PID
Write-Host "Launching the game..."
$p = Start-Process -FilePath "$WorkspaceRoot\build\desktop\ToyGame.exe" -WorkingDirectory "$WorkspaceRoot\build\desktop" -PassThru

# 3) Wait a few seconds for initialization
Start-Sleep -Seconds 1

# 4) Inject RenderDoc to capture one frame
Write-Host "Injecting RenderDoc into process ID $($p.Id)..."
& "C:\Program Files\RenderDoc\renderdoccmd.exe" inject --PID $($p.Id) --capture-file "$WorkspaceRoot\captures\ToyGame.rdc"

# 5) Wait for the game to exit
Write-Host "Waiting for game to exit..."
$p.WaitForExit()

# 6) Completion message
Write-Host "Done. Capture(s) saved to captures folder."

# 7) Find the latest .rdc file and open
Write-Host "Opening latest capture in RenderDoc..."
$latest = Get-ChildItem "$WorkspaceRoot\captures" -Filter "*.rdc" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
    Start-Process -FilePath "C:\Program Files\RenderDoc\qrenderdoc.exe" -ArgumentList $latest.FullName
} else {
    Write-Error "No .rdc files found in captures folder."
}
