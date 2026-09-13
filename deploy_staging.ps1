# Deploy to Staging Environment
# Target: staging-erp.droob-albayan.ly (IIS KineticStaging)
# Server: 65.21.213.78
# Path: C:\kinetic\staging-erp

param(
    [string]$GitHubToken = "",
    [string]$StagingPath = "C:\kinetic\staging-erp",
    [string]$ServerHost = "65.21.213.78"
)

Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "🚀 Kinetic ERP - Staging Deployment Script" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify local directory
Write-Host "📁 Step 1: Checking staging directory..." -ForegroundColor Yellow
if (-Not (Test-Path $StagingPath)) {
    Write-Host "   ⚠️ Directory not found: $StagingPath" -ForegroundColor Red
    Write-Host "   Creating directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $StagingPath -Force | Out-Null
    Write-Host "   ✅ Created: $StagingPath" -ForegroundColor Green
} else {
    Write-Host "   ✅ Directory exists: $StagingPath" -ForegroundColor Green
}

# Step 2: Download latest artifact from GitHub
Write-Host ""
Write-Host "📥 Step 2: Downloading kinetic-web.zip from GitHub..." -ForegroundColor Yellow

$repoOwner = "AdilAli76"
$repoName = "Itqan"
$artifactName = "build-artifacts"

# Get the latest workflow run
Write-Host "   Getting latest CI workflow run..." -ForegroundColor Gray
$workflowUrl = "https://api.github.com/repos/$repoOwner/$repoName/actions/runs?event=push&status=completed&limit=1"
$headers = @{}
if ($GitHubToken) {
    $headers["Authorization"] = "token $GitHubToken"
}

try {
    $runs = Invoke-RestMethod -Uri $workflowUrl -Headers $headers -ErrorAction Stop
    if ($runs.workflow_runs.Count -eq 0) {
        Write-Host "   ❌ No completed workflow runs found" -ForegroundColor Red
        exit 1
    }

    $latestRun = $runs.workflow_runs[0]
    $runId = $latestRun.id
    Write-Host "   ✅ Latest run ID: $runId" -ForegroundColor Green

    # Get artifacts from this run
    Write-Host "   Getting artifacts from run..." -ForegroundColor Gray
    $artifactsUrl = "https://api.github.com/repos/$repoOwner/$repoName/actions/runs/$runId/artifacts"
    $artifacts = Invoke-RestMethod -Uri $artifactsUrl -Headers $headers -ErrorAction Stop

    $buildArtifact = $artifacts.artifacts | Where-Object { $_.name -eq $artifactName }
    if (-Not $buildArtifact) {
        Write-Host "   ❌ Artifact '$artifactName' not found" -ForegroundColor Red
        exit 1
    }

    $downloadUrl = $buildArtifact.archive_download_url
    Write-Host "   ✅ Found artifact: $artifactName" -ForegroundColor Green

    # Download the artifact
    $zipPath = Join-Path $env:TEMP "kinetic-web-artifact.zip"
    Write-Host "   Downloading to: $zipPath" -ForegroundColor Gray

    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -Headers $headers -ErrorAction Stop
    Write-Host "   ✅ Downloaded successfully" -ForegroundColor Green

    # Extract the artifact
    Write-Host "   Extracting artifact..." -ForegroundColor Gray
    $extractPath = Join-Path $env:TEMP "kinetic-web-extract"
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    Write-Host "   ✅ Extracted" -ForegroundColor Green

    # Find kinetic-web.zip inside
    $webZipPath = Get-ChildItem -Path $extractPath -Filter "kinetic-web.zip" -Recurse | Select-Object -First 1
    if (-Not $webZipPath) {
        Write-Host "   ❌ kinetic-web.zip not found in artifact" -ForegroundColor Red
        exit 1
    }

    $webZipPath = $webZipPath.FullName
    Write-Host "   ✅ Found kinetic-web.zip" -ForegroundColor Green

} catch {
    Write-Host "   ❌ Error downloading artifact: $_" -ForegroundColor Red
    exit 1
}

# Step 3: Backup current staging
Write-Host ""
Write-Host "💾 Step 3: Backing up current staging..." -ForegroundColor Yellow
$backupPath = "$StagingPath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
if (Test-Path "$StagingPath\*") {
    Copy-Item -Path "$StagingPath\*" -Destination $backupPath -Recurse -Force
    Write-Host "   ✅ Backup created: $backupPath" -ForegroundColor Green
} else {
    Write-Host "   ⓘ No previous files to backup" -ForegroundColor Gray
}

# Step 4: Extract new build to staging
Write-Host ""
Write-Host "📦 Step 4: Deploying new build to staging..." -ForegroundColor Yellow
Write-Host "   Extracting kinetic-web.zip to $StagingPath..." -ForegroundColor Gray

# Clear staging directory
Get-ChildItem -Path $StagingPath -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $StagingPath -Directory | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

# Extract new build
Expand-Archive -Path $webZipPath -DestinationPath $StagingPath -Force
Write-Host "   ✅ Build deployed to staging" -ForegroundColor Green

# Step 5: Verify deployment
Write-Host ""
Write-Host "✅ Step 5: Verifying deployment..." -ForegroundColor Yellow
$indexHtml = Join-Path $StagingPath "index.html"
if (Test-Path $indexHtml) {
    Write-Host "   ✅ index.html found" -ForegroundColor Green
    $fileCount = (Get-ChildItem -Path $StagingPath -Recurse | Measure-Object).Count
    Write-Host "   ✅ Total files: $fileCount" -ForegroundColor Green
} else {
    Write-Host "   ❌ index.html not found - deployment may have failed" -ForegroundColor Red
    exit 1
}

# Step 6: IIS Application Pool Recycle
Write-Host ""
Write-Host "♻️ Step 6: Recycling IIS Application Pool..." -ForegroundColor Yellow
try {
    Import-Module WebAdministration -ErrorAction Stop
    Restart-WebAppPool -Name "KineticStaging" -ErrorAction SilentlyContinue
    Write-Host "   ✅ Application pool recycled (if IIS available)" -ForegroundColor Green
} catch {
    Write-Host "   ⓘ IIS not available locally (this is normal for local deployment)" -ForegroundColor Gray
}

# Step 7: Summary
Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✅ DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "📍 Staging URL: http://staging-erp.droob-albayan.ly:8080/" -ForegroundColor Green
Write-Host "📍 Local Path: $StagingPath" -ForegroundColor Green
Write-Host "💾 Backup: $backupPath" -ForegroundColor Green
Write-Host ""
Write-Host "🔄 Next Steps:" -ForegroundColor Yellow
Write-Host "   1. Open the staging URL in your browser"
Write-Host "   2. Test all features"
Write-Host "   3. If issues, restore from backup"
Write-Host "   4. Once verified, promote to production"
Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan
