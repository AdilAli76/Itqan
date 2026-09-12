<#
.SYNOPSIS
    يأخذ نسخة احتياطية من قاعدة البيانات والمرفقات.
    
.DESCRIPTION
    ينسخ قاعدة البيانات كاملةً والملفات المرفوعة قبل أي ترقية.
    
.PARAMETER Database
    اسم قاعدة البيانات (مثال: KineticEnterprise)
    
.PARAMETER UploadsPath
    مسار مجلد المرفقات (مثال: C:\kinetic\backend\uploads)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$Database,
    [Parameter(Mandatory = $false)] [string]$UploadsPath
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

function Step($n, $t) { Write-Host "`n[$n] $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "    $t" -ForegroundColor Green }
function Warn($t) { Write-Host "    $t" -ForegroundColor Yellow }

$backupRoot = 'C:\kinetic-backups'
if (-not (Test-Path $backupRoot)) {
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
}

$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$backupDir = Join-Path $backupRoot $timestamp
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Step 1 "نسخ قاعدة البيانات: $Database"

try {
    # تحقق من وجود SQL Server
    $sqlPath = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Binn\sqlcmd.exe'
    if (-not (Test-Path $sqlPath)) {
        $sqlPath = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn\sqlcmd.exe'
    }
    if (-not (Test-Path $sqlPath)) {
        throw "لم نعثر على sqlcmd.exe — تأكد من تثبيت SQL Server"
    }
    
    $backupFile = Join-Path $backupDir "$Database.bak"
    $backupQuery = "BACKUP DATABASE [$Database] TO DISK = N'$backupFile' WITH NOFORMAT, NOINIT, NAME = N'$Database', SKIP, NOREWIND, NOUNLOAD, STATS = 10;"
    
    & $sqlPath -S "(local)" -E -Q $backupQuery
    if ($LASTEXITCODE -eq 0) {
        Ok "تم نسخ قاعدة البيانات: $backupFile"
    } else {
        throw "فشل النسخ الاحتياطي لقاعدة البيانات (رمز: $LASTEXITCODE)"
    }
    
} catch {
    Warn "تعذّر نسخ قاعدة البيانات: $_"
    throw $_
}

# نسخ المرفقات
if ($UploadsPath -and (Test-Path $UploadsPath)) {
    Step 2 "نسخ المرفقات من: $UploadsPath"
    $uploadBackup = Join-Path $backupDir 'uploads'
    Copy-Item $UploadsPath $uploadBackup -Recurse -Force -ErrorAction Continue
    $size = [math]::Round((Get-ChildItem $uploadBackup -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
    Ok "تم نسخ المرفقات ($size ميغابايت)"
} else {
    Warn "لا مجلد مرفقات أو لم يُحدَّد"
}

# تنظيف النسخ القديمة (احتفظ بآخر 7 نسخ فقط)
Step 3 "تنظيف النسخ القديمة"
$backups = @(Get-ChildItem -Path $backupRoot -Directory | Sort-Object Name -Descending)
if ($backups.Count -gt 7) {
    $toDelete = $backups | Select-Object -Skip 7
    foreach ($old in $toDelete) {
        Remove-Item $old -Recurse -Force -ErrorAction Continue
        Warn "حذفت النسخة القديمة: $($old.Name)"
    }
}

Write-Host "`n✅ تمّ النسخ الاحتياطي بنجاح في: $backupDir" -ForegroundColor Green

exit 0
