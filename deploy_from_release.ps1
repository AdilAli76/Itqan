# Deploy Kinetic v2.0.1 from GitHub Release
# Run this directly on the server

param(
    [string]$ReleaseTag = "v2.0.1",
    [string]$DeployPath = "C:\kinetic-staging"
)

Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "🚀 Kinetic ERP - Direct Deploy from GitHub Release" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Step 1: Download Release
Write-Host "📥 Step 1: Downloading Release $ReleaseTag..." -ForegroundColor Yellow

$repoOwner = "AdilAli76"
$repoName = "Itqan"

# Get release info
$releaseUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/tags/$ReleaseTag"
Write-Host "   Fetching release info from GitHub..." -ForegroundColor Gray

try {
    $release = Invoke-RestMethod -Uri $releaseUrl -ErrorAction Stop
    Write-Host "   ✅ Found Release: $($release.tag_name)" -ForegroundColor Green
    Write-Host "   📝 Name: $($release.name)" -ForegroundColor Gray
} catch {
    Write-Host "   ❌ Release not found: $_" -ForegroundColor Red
    exit 1
}

# Find kinetic-web.zip in assets
$webZipAsset = $release.assets | Where-Object { $_.name -eq "kinetic-web.zip" }
if (-Not $webZipAsset) {
    Write-Host "   ❌ kinetic-web.zip not found in release assets" -ForegroundColor Red
    exit 1
}

$downloadUrl = $webZipAsset.browser_download_url
Write-Host "   ✅ Found kinetic-web.zip ($([math]::Round($webZipAsset.size / 1MB, 2)) MB)" -ForegroundColor Green

# Download the file
Write-Host "   Downloading..." -ForegroundColor Gray
$tempZip = Join-Path $env:TEMP "kinetic-web-$ReleaseTag.zip"

try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -ErrorAction Stop
    Write-Host "   ✅ Downloaded to: $tempZip" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Download failed: $_" -ForegroundColor Red
    exit 1
}

# Step 2: Backup current
Write-Host ""
Write-Host "💾 Step 2: Backing up current deployment..." -ForegroundColor Yellow

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = "$DeployPath.backup.$timestamp"

if (Test-Path $DeployPath) {
    Write-Host "   Creating backup: $backupPath" -ForegroundColor Gray
    Copy-Item $DeployPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "   ✅ Backup created" -ForegroundColor Green
    $fileCount = (Get-ChildItem -Path $backupPath -Recurse | Measure-Object).Count
    Write-Host "   📊 Backed up $fileCount files" -ForegroundColor Gray
} else {
    Write-Host "   ⓘ No previous deployment to backup" -ForegroundColor Gray
}

# Step 3: Deploy new build
Write-Host ""
Write-Host "📦 Step 3: Deploying new build..." -ForegroundColor Yellow

# Clean directory
Write-Host "   Cleaning deployment directory..." -ForegroundColor Gray
try {
    Get-ChildItem -Path $DeployPath -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    Get-ChildItem -Path $DeployPath -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
} catch {}

# Extract new build
Write-Host "   Extracting new build..." -ForegroundColor Gray
try {
    Expand-Archive -Path $tempZip -DestinationPath $DeployPath -Force -ErrorAction Stop
    Write-Host "   ✅ Build extracted successfully" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Extraction failed: $_" -ForegroundColor Red
    Write-Host "   🔄 Restoring from backup..." -ForegroundColor Yellow
    Remove-Item $DeployPath -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item $backupPath $DeployPath -Recurse -Force
    exit 1
}

# Step 4: Verify deployment
Write-Host ""
Write-Host "✅ Step 4: Verifying deployment..." -ForegroundColor Yellow

$indexHtml = Join-Path $DeployPath "index.html"
if (Test-Path $indexHtml) {
    Write-Host "   ✅ index.html found" -ForegroundColor Green
    $fileCount = (Get-ChildItem -Path $DeployPath -Recurse | Measure-Object).Count
    Write-Host "   📊 Total files deployed: $fileCount" -ForegroundColor Green

    # Check main.dart.js
    $mainJs = Get-ChildItem -Path $DeployPath -Recurse -Filter "main.dart.js" | Select-Object -First 1
    if ($mainJs) {
        $size = [math]::Round($mainJs.Length / 1MB, 2)
        Write-Host "   📄 main.dart.js: $size MB" -ForegroundColor Gray
    }
} else {
    Write-Host "   ❌ index.html not found - deployment failed" -ForegroundColor Red
    Write-Host "   🔄 Restoring from backup..." -ForegroundColor Yellow
    Remove-Item $DeployPath -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item $backupPath $DeployPath -Recurse -Force
    exit 1
}

# Step 5: Restart IIS
Write-Host ""
Write-Host "♻️ Step 5: Restarting IIS..." -ForegroundColor Yellow

try {
    Import-Module WebAdministration -ErrorAction Stop
    Write-Host "   Stopping application pool: KineticStaging" -ForegroundColor Gray
    Stop-WebAppPool -Name "KineticStaging" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "   Starting application pool: KineticStaging" -ForegroundColor Gray
    Start-WebAppPool -Name "KineticStaging" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "   ✅ IIS restarted successfully" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️ Warning: Could not restart IIS: $_" -ForegroundColor Yellow
    Write-Host "   (Try restarting manually if needed)" -ForegroundColor Gray
}

# Step 6: Summary
Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✅ DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "📍 Release:      $ReleaseTag" -ForegroundColor Green
Write-Host "📍 Deployed to:  $DeployPath" -ForegroundColor Green
Write-Host "💾 Backup:       $backupPath" -ForegroundColor Green
Write-Host "🌐 URL:          http://staging-erp.droob-albayan.ly:8080/" -ForegroundColor Green
Write-Host ""
Write-Host "⏰ Deployment time: $(Get-Date)" -ForegroundColor Gray
Write-Host ""
Write-Host "🔄 Next steps:" -ForegroundColor Yellow
Write-Host "   1. Open the staging URL in your browser"
Write-Host "   2. Test the new version"
Write-Host "   3. Check browser console (F12) for any errors"
Write-Host "   4. If issues, run: deploy_from_release.ps1"
Write-Host "      (It will restore from backup)"
Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan

# Cleanup
Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
