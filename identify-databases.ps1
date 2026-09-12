# Script to identify Production and Staging databases
# Detects database names, sizes, and purposes

param(
    [string]$ServerName = "(local)",
    [string]$SearchPattern = "*inetic*"
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Database Detection Script" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Server: $ServerName`n" -ForegroundColor Yellow

# Get all databases matching pattern
Write-Host "[1] Scanning for Kinetic databases..." -ForegroundColor Yellow

$query = @"
SELECT
    name AS DatabaseName,
    size * 8 / 1024.0 AS SizeMB,
    CASE
        WHEN name LIKE '%staging%' OR name LIKE '%stage%' OR name LIKE '%test%' OR name LIKE '%dev%'
        THEN 'STAGING/TEST'
        WHEN name LIKE '%prod%' OR name LIKE '%production%'
        THEN 'PRODUCTION'
        ELSE 'UNKNOWN'
    END AS Purpose,
    state_desc AS Status,
    create_date AS CreatedDate
FROM sys.databases
WHERE name LIKE 'KineticEnterprise%'
   OR name LIKE '%inetic%'
   OR name LIKE '%taging%'
ORDER BY create_date DESC
"@

try {
    $databases = sqlcmd -S $ServerName -Q $query -h -1 -W 256 2>&1 | ConvertFrom-Csv -Delimiter ' '

    if ($databases.Count -eq 0) {
        Write-Host "No databases found. Trying alternative query..." -ForegroundColor Yellow
        $databases = sqlcmd -S $ServerName -Q "SELECT name FROM sys.databases ORDER BY name" 2>&1 | Where-Object {$_ -match "inetic"}
    }

    if ($databases) {
        Write-Host "`n[FOUND DATABASES]" -ForegroundColor Green
        foreach ($db in $databases) {
            $dbName = $db.Trim()
            if ($dbName) {
                Write-Host "  • $dbName" -ForegroundColor Cyan
            }
        }
    }
}
catch {
    Write-Host "Error querying databases: $_" -ForegroundColor Red
}

# Simple alternative: list all databases containing "kinetic"
Write-Host "`n[2] All databases containing 'kinetic':" -ForegroundColor Yellow
sqlcmd -S $ServerName -Q "SELECT name FROM sys.databases WHERE name LIKE '%inetic%' OR name LIKE '%taging%' OR name LIKE '%test%' ORDER BY name" -h -1

Write-Host "`n[3] Database size info:" -ForegroundColor Yellow
sqlcmd -S $ServerName -Q @"
SELECT
    name,
    CAST(CAST(size * 8 AS DECIMAL(18,2)) / 1024.0 AS VARCHAR(20)) + ' MB' as Size
FROM sys.databases
WHERE name LIKE '%inetic%' OR name LIKE '%taging%' OR name LIKE '%test%'
ORDER BY name
"@ -h -1

Write-Host "`n[4] Connection test to each database:" -ForegroundColor Yellow
$dbNames = sqlcmd -S $ServerName -Q "SELECT name FROM sys.databases WHERE name LIKE '%inetic%' OR name LIKE '%taging%' OR name LIKE '%test%' ORDER BY name" -h -1 -W 256

foreach ($db in $dbNames) {
    $db = $db.Trim()
    if ($db) {
        try {
            $test = sqlcmd -S $ServerName -d $db -Q "SELECT @@SERVERNAME as [Server], DB_NAME() as [Database]" 2>&1
            if ($?) {
                Write-Host "  ✅ $db" -ForegroundColor Green
            } else {
                Write-Host "  ❌ $db - Connection failed" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "  ❌ $db - Error: $_" -ForegroundColor Red
        }
    }
}

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Run these commands with the database names above:" -ForegroundColor Yellow
Write-Host "`n# Apply migrations to STAGING:" -ForegroundColor Cyan
Write-Host "sqlcmd -S $ServerName -d STAGING_DB_NAME -Q `"CREATE TABLE platform_organizations ...`"" -ForegroundColor Gray
Write-Host "`n# Update staging admin email:" -ForegroundColor Cyan
Write-Host "sqlcmd -S $ServerName -d STAGING_DB_NAME -Q `"UPDATE app_users SET email='staging-admin@droob-albayan.ly' WHERE username='admin'`"" -ForegroundColor Gray
