# Migration Script: Apply Platform Tables
# Usage: .\apply_migration.ps1 -ServerName "SERVER_NAME" -DatabaseName "KineticEnterprise"

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerName,

    [Parameter(Mandatory=$false)]
    [string]$DatabaseName = "KineticEnterprise",

    [Parameter(Mandatory=$false)]
    [string]$Username = "",

    [Parameter(Mandatory=$false)]
    [string]$Password = ""
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MigrationFile = Join-Path $ScriptDir "001_create_platform_tables.sql"

if (-not (Test-Path $MigrationFile)) {
    Write-Error "Migration file not found: $MigrationFile"
    exit 1
}

Write-Host "Applying migration to $ServerName.$DatabaseName..." -ForegroundColor Cyan

try {
    $ConnectionString = "Server=$ServerName;Database=$DatabaseName;Connection Timeout=30;"

    if ($Username -and $Password) {
        $ConnectionString += "User Id=$Username;Password=$Password;"
    } else {
        $ConnectionString += "Integrated Security=true;"
    }

    $SqlContent = Get-Content -Path $MigrationFile -Raw

    $Connection = New-Object System.Data.SqlClient.SqlConnection
    $Connection.ConnectionString = $ConnectionString
    $Connection.Open()

    $Command = $Connection.CreateCommand()
    $Command.CommandText = $SqlContent
    $Command.CommandTimeout = 300

    $Command.ExecuteNonQuery()

    Write-Host "✅ Migration applied successfully!" -ForegroundColor Green

    $Connection.Close()
}
catch {
    Write-Error "❌ Migration failed: $_"
    exit 1
}
