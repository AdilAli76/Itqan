#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Kinetic ERP v1.6.6 Deployment Script
    Deploys the built package to a target server (staging or production)

.DESCRIPTION
    This script handles the complete deployment process:
    1. Extract the package ZIP
    2. Apply database migration
    3. Deploy backend files
    4. Deploy frontend files
    5. Restart IIS
    6. Verify deployment

.PARAMETER Target
    Deployment target: 'staging' or 'production' (default: 'staging')

.PARAMETER Version
    Version number (e.g., '1.6.6', default: '1.6.6')

.PARAMETER ServerName
    Target server name or IP (default: 'localhost')

.PARAMETER DeployPath
    Target deployment path on server (default: 'C:\kinetic\')

.PARAMETER DatabaseServer
    Database server connection string

.PARAMETER DatabaseName
    Database name (default: 'kinetic_erp')

.EXAMPLE
    .\deploy-now.ps1 -Target staging -ServerName staging.example.com
    .\deploy-now.ps1 -Target production -ServerName prod.example.com -DeployPath "D:\applications\kinetic\"
#>

param(
    [ValidateSet('staging', 'production')]
    [string]$Target = 'staging',

    [string]$Version = '1.6.6',

    [string]$ServerName = 'localhost',

    [string]$DeployPath = 'C:\kinetic\',

    [string]$DatabaseServer = '.',

    [string]$DatabaseName = 'kinetic_erp'
)

# Color output
function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Cyan
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$packagePattern = "$projectRoot\kinetic_pkg_*.zip"

Write-Info "Kinetic ERP v$Version - Deployment to $Target"
Write-Info "Target Server: $ServerName"
Write-Info "Deploy Path: $DeployPath"
Write-Info ""

# Step 1: Find package
Write-Info "Step 1: Locating deployment package..."
$packages = @(Get-Item $packagePattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)

if ($packages.Count -eq 0) {
    Write-Error "No deployment package found matching: $packagePattern"
    Write-Info "Please run .\build-v1.6.6.ps1 first to create the package"
    exit 1
}

$package = $packages[0]
Write-Success "Found package: $($package.Name) ($('{0:N2}' -f ($package.Length / 1MB)) MB)"

# Step 2: Extract package
Write-Info ""
Write-Info "Step 2: Extracting deployment package..."
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$extractPath = "$projectRoot\kinetic_extract_$timestamp"

try {
    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force | Out-Null
    }
    Expand-Archive -Path $package.FullName -DestinationPath $extractPath -Force
    Write-Success "Package extracted to: $extractPath"
}
catch {
    Write-Error "Failed to extract package: $_"
    exit 1
}

# Verify extraction
$versionFolder = Join-Path $extractPath $Version
if (-not (Test-Path $versionFolder)) {
    Write-Error "Extracted package missing version folder: $versionFolder"
    exit 1
}

Write-Success "Verified version folder exists: $versionFolder"

# Step 3: Prepare target server (for remote deployment)
if ($ServerName -ne 'localhost') {
    Write-Info ""
    Write-Info "Step 3: Preparing remote server: $ServerName"

    # Test connection
    $testConnection = Test-NetConnection -ComputerName $ServerName -Port 445 -WarningAction SilentlyContinue
    if (-not $testConnection.TcpTestSucceeded) {
        Write-Error "Cannot connect to server: $ServerName"
        exit 1
    }

    Write-Success "Connected to server: $ServerName"

    # Map network drive if needed
    $remotePath = "\\$ServerName\c$\kinetic_pkg_deploy_$timestamp"
    Write-Info "Creating temporary share: $remotePath"

    if (-not (Test-Path $remotePath)) {
        New-Item -ItemType Directory -Path $remotePath -Force | Out-Null
    }

    Write-Success "Remote path prepared"
}
else {
    Write-Info ""
    Write-Info "Step 3: Local deployment (no remote connection needed)"
}

# Step 4: Database Migration
Write-Info ""
Write-Info "Step 4: Applying database migration..."

$migrationFile = Join-Path $versionFolder "MIGRATIONS_$Version.sql"
if (-not (Test-Path $migrationFile)) {
    Write-Warning "Migration file not found: $migrationFile"
    Write-Info "Skipping database migration (may already be applied)"
}
else {
    Write-Info "Executing: $DatabaseServer / $DatabaseName"

    try {
        $sqlCmd = "sqlcmd -S `"$DatabaseServer`" -d `"$DatabaseName`" -i `"$migrationFile`" -v ON_ERROR=EXIT"
        Invoke-Expression $sqlCmd

        if ($LASTEXITCODE -eq 0) {
            Write-Success "Database migration completed successfully"
        }
        else {
            Write-Warning "Database migration exit code: $LASTEXITCODE (may already be applied)"
        }
    }
    catch {
        Write-Warning "Database migration error: $_"
        Write-Info "Continuing with deployment..."
    }
}

# Step 5: Backup current deployment
Write-Info ""
Write-Info "Step 5: Creating backup of current deployment..."

if (Test-Path $DeployPath) {
    $backupPath = "$DeployPath.backup_$timestamp"
    Write-Info "Backing up to: $backupPath"

    try {
        Copy-Item $DeployPath $backupPath -Recurse -Force
        Write-Success "Backup created successfully"
    }
    catch {
        Write-Warning "Backup failed: $_"
        Write-Info "Continuing with deployment..."
    }
}
else {
    Write-Info "No existing deployment found (fresh install)"
    New-Item -ItemType Directory -Path $DeployPath -Force | Out-Null
}

# Step 6: Stop IIS
Write-Info ""
Write-Info "Step 6: Stopping IIS Application Pool..."

try {
    if ($ServerName -eq 'localhost') {
        iisreset /stop
        Start-Sleep -Seconds 3
        Write-Success "IIS stopped"
    }
    else {
        Write-Info "Stopping IIS on remote server..."
        Invoke-Command -ComputerName $ServerName -ScriptBlock {
            iisreset /stop
        } -ErrorAction Stop
        Start-Sleep -Seconds 3
        Write-Success "Remote IIS stopped"
    }
}
catch {
    Write-Warning "IIS stop failed: $_ (attempting to continue)"
}

# Step 7: Deploy files
Write-Info ""
Write-Info "Step 7: Deploying application files..."

try {
    Write-Info "Copying backend files..."
    robocopy "$versionFolder\" "$DeployPath\" /MIR /XD wwwroot /XF *.sql | Out-Null
    Write-Success "Backend files deployed"

    Write-Info "Copying frontend files..."
    $wwwrootSource = Join-Path $versionFolder "wwwroot"
    $wwwrootTarget = Join-Path $DeployPath "wwwroot"

    if (Test-Path $wwwrootSource) {
        robocopy "$wwwrootSource\" "$wwwrootTarget\" /MIR | Out-Null
        Write-Success "Frontend files deployed"
    }
    else {
        Write-Warning "Frontend files not found in package"
    }
}
catch {
    Write-Error "File deployment failed: $_"
    exit 1
}

# Step 8: Start IIS
Write-Info ""
Write-Info "Step 8: Starting IIS Application Pool..."

try {
    if ($ServerName -eq 'localhost') {
        iisreset /start
        Start-Sleep -Seconds 5
        Write-Success "IIS started"
    }
    else {
        Write-Info "Starting IIS on remote server..."
        Invoke-Command -ComputerName $ServerName -ScriptBlock {
            iisreset /start
        } -ErrorAction Stop
        Start-Sleep -Seconds 5
        Write-Success "Remote IIS started"
    }
}
catch {
    Write-Error "IIS start failed: $_"
    exit 1
}

# Step 9: Verification
Write-Info ""
Write-Info "Step 9: Verifying deployment..."

$maxRetries = 5
$retryCount = 0
$healthUrl = if ($ServerName -eq 'localhost') {
    'http://localhost/api/health'
}
else {
    "http://$ServerName/api/health"
}

do {
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -Method Get -TimeoutSec 5 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Success "API health check passed"
            break
        }
    }
    catch {
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Write-Info "Health check attempt $retryCount/$maxRetries (waiting...)..."
            Start-Sleep -Seconds 2
        }
    }
} while ($retryCount -lt $maxRetries)

if ($retryCount -ge $maxRetries) {
    Write-Warning "API health check did not respond after $maxRetries attempts"
    Write-Info "Server may still be starting up - please verify manually"
}

# Cleanup
Write-Info ""
Write-Info "Step 10: Cleanup..."
Write-Info "Removing temporary extract folder..."
Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Write-Success "Cleanup complete"

# Final summary
Write-Info ""
Write-Success "========================================="
Write-Success "Deployment to $Target completed!"
Write-Success "========================================="
Write-Success ""
Write-Success "Version: $Version"
Write-Success "Target: $Target ($ServerName)"
Write-Success "Deploy Path: $DeployPath"
Write-Success "Backup: $(if (Test-Path "$DeployPath.backup_$timestamp") { "$DeployPath.backup_$timestamp" } else { 'N/A' })"
Write-Success ""
Write-Success "Next Steps:"
Write-Success "1. Verify application is running"
Write-Success "2. Test all features on $Target environment"
Write-Success "3. Check application logs for errors"
Write-Success "4. Run comprehensive test suite"
Write-Success ""
Write-Info "For deployment checklist, see: DEPLOYMENT_CHECKLIST_V1.6.6.md"
Write-Info "For troubleshooting, see: docs/V1.6.6_FINAL_STATUS.md"
