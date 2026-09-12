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

# Apply all SQL migration files in order
$MigrationFiles = @(
    "001_create_platform_tables.sql",
    "002_supplier_invoice_enhancements.sql"
) | ForEach-Object { Join-Path $ScriptDir $_ }

$MigrationFiles | ForEach-Object {
    if (-not (Test-Path $_)) {
        Write-Error "Migration file not found: $_"
        exit 1
    }
}

Write-Host "Applying migrations to $ServerName.$DatabaseName..." -ForegroundColor Cyan

try {
    $ConnectionString = "Server=$ServerName;Database=$DatabaseName;Connection Timeout=30;"

    if ($Username -and $Password) {
        $ConnectionString += "User Id=$Username;Password=$Password;"
    } else {
        $ConnectionString += "Integrated Security=true;"
    }

    $Connection = New-Object System.Data.SqlClient.SqlConnection
    $Connection.ConnectionString = $ConnectionString
    $Connection.Open()

    $MigrationFiles | ForEach-Object {
        $SqlContent = Get-Content -Path $_ -Raw
        $FileName = Split-Path -Leaf $_

        Write-Host "  Applying: $FileName..." -ForegroundColor Cyan

        $Command = $Connection.CreateCommand()
        $Command.CommandText = $SqlContent
        $Command.CommandTimeout = 300

        $Command.ExecuteNonQuery()
        Write-Host "  ✅ $FileName applied" -ForegroundColor Green
    }

    Write-Host "✅ All migrations applied successfully!" -ForegroundColor Green

    $Connection.Close()
}
catch {
    Write-Error "❌ Migration failed: $_"
    exit 1
}
