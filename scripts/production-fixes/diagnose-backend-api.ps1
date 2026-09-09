#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Kinetic ERP v1.6.6 - Backend API & SQL Server Diagnostic
    Comprehensive troubleshooting for API connectivity issues

.DESCRIPTION
    This script diagnoses:
    1. SQL Server connectivity
    2. Named pipes vs TCP/IP protocol
    3. IIS app pool status
    4. Backend application health
    5. Database connection string validation
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
Write-Info "Kinetic ERP v1.6.6 - Backend Diagnostics"
Write-Info "==========================================="
Write-Info ""

# STEP 1: SQL Server Status
Write-Info "STEP 1: SQL Server Service Status"
Write-Info "────────────────────────────────"

$sqlServices = Get-Service | Where-Object { $_.Name -like '*MSSQL*' }
if ($sqlServices) {
    foreach ($svc in $sqlServices) {
        $status = if ($svc.Status -eq 'Running') { '✓' } else { '✗' }
        Write-Info "  $status $($svc.Name) - $($svc.Status)"
    }
} else {
    Write-Error "No SQL Server services found"
}

Write-Info ""

# STEP 2: Test TCP Connection
Write-Info "STEP 2: SQL Server TCP/IP Connectivity"
Write-Info "──────────────────────────────────────"

$tcpTest = Test-NetConnection -ComputerName 'localhost' -Port 1433 -WarningAction SilentlyContinue
if ($tcpTest.TcpTestSucceeded) {
    Write-Success "TCP port 1433 is open and reachable"
} else {
    Write-Warning "TCP port 1433 NOT reachable - SQL Server may not have TCP/IP enabled"
}

Write-Info ""

# STEP 3: Named Instances
Write-Info "STEP 3: SQL Server Named Instances"
Write-Info "──────────────────────────────────"

$regPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server'
$instances = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Select-Object 'InstalledInstances'
if ($instances) {
    Write-Info "Installed instances: $($instances.InstalledInstances -join ', ')"
}

Write-Info ""

# STEP 4: Test sqlcmd Connection
Write-Info "STEP 4: Direct sqlcmd Connection Test"
Write-Info "──────────────────────────────────────"

Write-Info "Testing: sqlcmd -S (local) -Q 'SELECT @@VERSION' -E"
$result = & sqlcmd -S '(local)' -Q 'SELECT @@VERSION' -E -l 5 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Success "✓ Successfully connected to SQL Server"
    Write-Info "$($result[0])"
} else {
    Write-Error "✗ Failed to connect to SQL Server"
    Write-Info "Error: $($result -join ' ')"
    Write-Warning "Try with different connection string: 'localhost', '127.0.0.1', '.', 'SQLEXPRESS'"
}

Write-Info ""

# STEP 5: Test Named Instance Connection
Write-Info "STEP 5: Named Instance Connection Test"
Write-Info "──────────────────────────────────────"

$instances = @('(local)\SQLEXPRESS', '(local)\SQLEXPRESS01', '.\SQLEXPRESS', '.\SQLEXPRESS01')
foreach ($instance in $instances) {
    Write-Info "Testing: sqlcmd -S $instance -Q 'SELECT 1' -E"
    $result = & sqlcmd -S $instance -Q 'SELECT 1' -E -l 3 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "✓ Connected to: $instance"
    } else {
        Write-Warning "✗ Failed: $instance"
    }
}

Write-Info ""

# STEP 6: Check appsettings.Production.json
Write-Info "STEP 6: Backend Configuration Check"
Write-Info "───────────────────────────────────"

$appSettingsPath = 'C:\kinetic\appsettings.Production.json'
if (Test-Path $appSettingsPath) {
    Write-Success "Found: $appSettingsPath"

    $content = Get-Content $appSettingsPath | ConvertFrom-Json
    $connStr = $content.ConnectionStrings.DefaultConnection
    Write-Info "Connection String:"
    Write-Info "  $connStr"
} else {
    Write-Error "Missing: $appSettingsPath"
}

Write-Info ""

# STEP 7: IIS Application Pool Status
Write-Info "STEP 7: IIS Application Pool Status"
Write-Info "───────────────────────────────────"

$appPool = Get-WebAppPoolState -Name 'Kinetic' -ErrorAction SilentlyContinue
if ($appPool) {
    $status = if ($appPool.Value -eq 'Started') { '✓' } else { '✗' }
    Write-Info "$status Kinetic Pool: $($appPool.Value)"

    # Get process ID to check if it's actually running
    $pool = Get-IISAppPool -Name 'Kinetic'
    if ($pool.State -eq 'Started') {
        Write-Success "App pool is running"
    }
} else {
    Write-Error "Kinetic app pool not found"
}

Write-Info ""

# STEP 8: Test Backend API Health
Write-Info "STEP 8: Backend API Health Check"
Write-Info "────────────────────────────────"

$apiUrl = 'http://localhost/api/health'
Write-Info "Testing: $apiUrl"

try {
    $response = Invoke-WebRequest -Uri $apiUrl -Method Get -TimeoutSec 5 -ErrorAction Stop
    Write-Success "✓ API responded with status: $($response.StatusCode)"
    Write-Info "Response type: $($response.Headers.'Content-Type')"
    Write-Info "Response length: $($response.Content.Length) bytes"

    if ($response.StatusCode -eq 200) {
        Write-Success "✓ API is healthy"
    }
} catch {
    Write-Error "✗ API not responding: $($_.Exception.Message)"

    # Try to get error details
    if ($_.Exception.Response) {
        Write-Info "HTTP Status: $($_.Exception.Response.StatusCode)"
    }
}

Write-Info ""

# STEP 9: Recommendations
Write-Info "STEP 9: Recommendations"
Write-Info "──────────────────────"

Write-Info ""
Write-Info "If SQL Server connection fails:"
Write-Info "  1. Enable TCP/IP protocol (SQL Server Configuration Manager)"
Write-Info "  2. Restart SQL Server service"
Write-Info "  3. Test with: sqlcmd -S localhost -U sa -P YOUR_PASSWORD"
Write-Info ""
Write-Info "If API still returns 500:"
Write-Info "  1. Check IIS logs: C:\inetpub\logs\LogFiles\W3SVC*\"
Write-Info "  2. Check Event Viewer Application logs"
Write-Info "  3. Verify appsettings.Production.json is correct"
Write-Info ""
Write-Info "If you need to reset the app pool:"
Write-Info "  iisreset /recycle /apppool:Kinetic"
Write-Info ""
