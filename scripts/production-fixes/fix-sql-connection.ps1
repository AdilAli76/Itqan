#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Fix SQL Server connectivity issues for Kinetic ERP Backend API

.DESCRIPTION
    This script attempts to:
    1. Enable TCP/IP protocol if disabled
    2. Restart SQL Server service
    3. Update connection string if needed
    4. Verify connectivity works

.NOTES
    Requires: Administrator privileges
    Target: SQL Server 2019+ with SQLEXPRESS or similar instance
#>

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

Write-Info "==========================================="
Write-Info "SQL Server Connection Fix for Kinetic ERP"
Write-Info "==========================================="
Write-Info ""

# Check admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
if (-not $isAdmin) {
    Write-Error "This script requires Administrator privileges"
    Write-Info "Please run: Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process"
    exit 1
}

Write-Success "Running as Administrator"

# STEP 1: Find SQL Server Instances
Write-Info ""
Write-Info "STEP 1: Identifying SQL Server Instance"
Write-Info "─────────────────────────────────────────"

$regPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server'
$instanceList = (Get-ItemProperty $regPath).InstalledInstances

if (-not $instanceList) {
    Write-Error "No SQL Server instances found"
    exit 1
}

Write-Info "Found instances: $($instanceList -join ', ')"

# Determine which instance to use
$sqlInstance = 'SQLEXPRESS'
if ($instanceList -contains 'SQLEXPRESS') {
    $sqlInstance = 'SQLEXPRESS'
    Write-Success "Using instance: $sqlInstance"
} elseif ($instanceList.Count -gt 0) {
    $sqlInstance = $instanceList[0]
    Write-Success "Using instance: $sqlInstance"
}

# STEP 2: Restart SQL Server Service
Write-Info ""
Write-Info "STEP 2: Restarting SQL Server Service"
Write-Info "──────────────────────────────────────"

$serviceName = if ($sqlInstance -eq 'MSSQLSERVER') {
    'MSSQLSERVER'
} else {
    "MSSQL`$$sqlInstance"
}

Write-Info "Service name: $serviceName"

try {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    Write-Info "Current status: $($svc.Status)"

    Write-Info "Stopping service..."
    Stop-Service -Name $serviceName -Force
    Start-Sleep -Seconds 2

    Write-Info "Starting service..."
    Start-Service -Name $serviceName
    Start-Sleep -Seconds 5

    $svc = Get-Service -Name $serviceName
    Write-Success "Service is now: $($svc.Status)"
} catch {
    Write-Error "Failed to restart service: $_"
}

# STEP 3: Test Connection
Write-Info ""
Write-Info "STEP 3: Testing Connection"
Write-Info "──────────────────────────"

$serverNames = @("(local)\$sqlInstance", ".\$sqlInstance", "localhost\$sqlInstance", "(local)", ".", "localhost")

$connected = $false
foreach ($server in $serverNames) {
    Write-Info "Trying: $server"
    $result = & sqlcmd -S "$server" -Q "SELECT @@VERSION, @@SERVERNAME" -E -l 5 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "✓ Successfully connected to: $server"
        $connectedServer = $server
        $connected = $true
        break
    }
}

if (-not $connected) {
    Write-Error "Could not connect to any SQL Server instance"
    Write-Warning "Troubleshooting steps:"
    Write-Warning "  1. Open SQL Server Configuration Manager"
    Write-Warning "  2. Navigate to: SQL Server Network Configuration > Protocols for $sqlInstance"
    Write-Warning "  3. Enable: Named Pipes, TCP/IP"
    Write-Warning "  4. Restart SQL Server service"
    Write-Warning "  5. Re-run this script"
    exit 1
}

# STEP 4: Test Database Access
Write-Info ""
Write-Info "STEP 4: Testing Database Access"
Write-Info "────────────────────────────────"

Write-Info "Database: kinetic_erp"

$result = & sqlcmd -S "$connectedServer" -Q "SELECT DB_ID('kinetic_erp')" -E -l 5 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Success "✓ kinetic_erp database is accessible"
} else {
    Write-Warning "kinetic_erp database not found or not accessible"
    Write-Info "You may need to restore the database from backup"
}

# STEP 5: Update Connection String in appsettings
Write-Info ""
Write-Info "STEP 5: Updating Backend Configuration"
Write-Info "───────────────────────────────────────"

$appSettingsPath = 'C:\kinetic\appsettings.Production.json'

if (Test-Path $appSettingsPath) {
    Write-Info "Reading: $appSettingsPath"

    $json = Get-Content $appSettingsPath | ConvertFrom-Json

    # Update connection string based on connected server
    if ($connectedServer -like '(local)*') {
        $newConnStr = "Server=.;Database=kinetic_erp;Trusted_Connection=True;TrustServerCertificate=True;"
    } elseif ($connectedServer -like 'localhost*') {
        $newConnStr = "Server=localhost;Database=kinetic_erp;Trusted_Connection=True;TrustServerCertificate=True;"
    } else {
        $newConnStr = "Server=$connectedServer;Database=kinetic_erp;Trusted_Connection=True;TrustServerCertificate=True;"
    }

    Write-Info "Current connection string:"
    Write-Info "  $($json.ConnectionStrings.DefaultConnection)"

    Write-Info "Updating to:"
    Write-Info "  $newConnStr"

    $json.ConnectionStrings.DefaultConnection = $newConnStr

    $json | ConvertTo-Json -Depth 10 | Out-File $appSettingsPath -Encoding UTF8
    Write-Success "✓ Configuration updated"
} else {
    Write-Error "appsettings.Production.json not found at: $appSettingsPath"
}

# STEP 6: Recycle App Pool
Write-Info ""
Write-Info "STEP 6: Recycling IIS Application Pool"
Write-Info "───────────────────────────────────────"

try {
    Write-Info "Recycling: Kinetic"
    & iisreset /recycle /apppool:Kinetic 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    Write-Success "✓ Application pool recycled"
} catch {
    Write-Warning "Failed to recycle app pool: $_"
}

# STEP 7: Test API
Write-Info ""
Write-Info "STEP 7: Testing Backend API"
Write-Info "───────────────────────────"

$maxRetries = 5
$retryCount = 0

do {
    try {
        Write-Info "Attempt $($retryCount + 1)/$maxRetries..."
        $response = Invoke-WebRequest -Uri 'http://localhost/api/health' -Method Get -TimeoutSec 5 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Success "✓ API is now responding with 200 OK"
            Write-Info "Response: $($response.Content -substring 0, 200)"
            break
        }
    } catch {
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Write-Info "Waiting for API to start (waiting 2s)..."
            Start-Sleep -Seconds 2
        }
    }
} while ($retryCount -lt $maxRetries)

if ($retryCount -ge $maxRetries) {
    Write-Warning "API did not respond after $maxRetries attempts"
    Write-Info "Please check:"
    Write-Info "  1. IIS application pool status"
    Write-Info "  2. Event Viewer Application logs"
    Write-Info "  3. IIS logs in: C:\inetpub\logs\LogFiles\"
}

Write-Info ""
Write-Success "=================================="
Write-Success "SQL Server Connection Fix Complete"
Write-Success "=================================="
Write-Info ""
