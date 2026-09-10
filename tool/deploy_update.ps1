&#65279;<#
.SYNOPSIS
    يفكّ حزمة النشر ويرقّي الموقع على الخادم.
    
.DESCRIPTION
    يُوقف الموقع والمجموعة، يفكّ الحزمة، ينسخ الملفات، ثم يعيد التشغيل.
    يسجّل البصمة في deploy.log للتحقق من الترقيات المستقبلية.
    
.PARAMETER Package
    مسار ملف الحزمة (kinetic_pkg_*.zip)
    
.PARAMETER Target
    جذر التثبيت (مثال: C:\kinetic-staging)
    
.PARAMETER SiteName
    اسم الموقع في IIS (مثال: KineticStaging)
    
.PARAMETER PoolName
    اسم مجموعة العمليات (مثال: KineticStagingPool)
    
.PARAMETER SkipDb
    تخطّي الترحيلات (تمّ تنفيذها للتوّ)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$Package,
    [Parameter(Mandatory = $true)] [string]$Target,
    [Parameter(Mandatory = $true)] [string]$SiteName,
    [Parameter(Mandatory = $true)] [string]$PoolName,
    [switch]$SkipDb
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

function Step($n, $t) { Write-Host "`n[$n] $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "    $t" -ForegroundColor Green }
function Warn($t) { Write-Host "    $t" -ForegroundColor Yellow }

# تحقق من وجود الحزمة
if (-not (Test-Path $Package)) {
    throw "الحزمة غير موجودة: $Package"
}

# احسب البصمة
$sha = (Get-FileHash -LiteralPath $Package -Algorithm SHA256).Hash
Step 0 "بصمة الحزمة: $sha"

# أوقف الموقع ومجموعة العمليات
Step 1 "إيقاف الموقع: $SiteName"
try {
    Stop-Website -Name $SiteName -ErrorAction Stop
    Ok "تم إيقاف الموقع"
} catch {
    Warn "تعذّر إيقاف الموقع (قد يكون متوقفاً): $_"
}

try {
    Stop-WebAppPool -Name $PoolName -ErrorAction Stop
    Ok "تم إيقاف مجموعة العمليات"
} catch {
    Warn "تعذّر إيقاف مجموعة العمليات: $_"
}

# انتظر قليلاً حتى يُغلق كل الملفات
Start-Sleep -Seconds 2

# فكّ الحزمة
Step 2 "فكّ الحزمة"
$extract = Join-Path $env:TEMP "kinetic-extract-$([DateTime]::Now.Ticks)"
New-Item -ItemType Directory -Force -Path $extract | Out-Null

try {
    Expand-Archive -LiteralPath $Package -DestinationPath $extract -Force
    Ok "تم فكّ الحزمة"
    
    # نسخ الملفات
    Step 3 "نسخ الملفات"
    
    # backend
    $backendSrc = Join-Path $extract 'backend'
    $backendDst = Join-Path $Target 'backend'
    if (Test-Path $backendSrc) {
        if (-not (Test-Path $backendDst)) {
            New-Item -ItemType Directory -Force -Path $backendDst | Out-Null
        }
        Copy-Item "$backendSrc\*" $backendDst -Recurse -Force -ErrorAction Continue
        Ok "تم نسخ backend"
    } else {
        Warn "backend غير موجود في الحزمة"
    }
    
    # SQL scripts
    $sqlSrc = Join-Path $extract 'sql'
    $sqlDst = Join-Path $Target 'sql'
    if (Test-Path $sqlSrc) {
        if (-not (Test-Path $sqlDst)) {
            New-Item -ItemType Directory -Force -Path $sqlDst | Out-Null
        }
        Copy-Item "$sqlSrc\*" $sqlDst -Recurse -Force -ErrorAction Continue
        Ok "تم نسخ SQL scripts"
    } else {
        Warn "sql غير موجود في الحزمة"
    }
    
    # tool
    $toolSrc = Join-Path $extract 'tool'
    $toolDst = Join-Path $Target 'tool'
    if (Test-Path $toolSrc) {
        if (-not (Test-Path $toolDst)) {
            New-Item -ItemType Directory -Force -Path $toolDst | Out-Null
        }
        Copy-Item "$toolSrc\*" $toolDst -Recurse -Force -ErrorAction Continue
        Ok "تم نسخ tool"
    } else {
        Warn "tool غير موجود في الحزمة"
    }
    
    # تنفيذ الترحيلات إذا لزم الأمر
    if (-not $SkipDb) {
        Step 4 "تنفيذ ترحيلات قاعدة البيانات"
        $migrationScript = Join-Path $backendDst 'migrate.ps1'
        if (Test-Path $migrationScript) {
            try {
                & $migrationScript -ErrorAction Stop
                Ok "تمّ الترحيل بنجاح"
            } catch {
                throw "فشل الترحيل: $_"
            }
        } else {
            Warn "لا سكريبت ترحيل — تخطّي الترحيلات"
        }
    } else {
        Ok "تخطّي الترحيلات (كما طُلب)"
    }
    
    # إعادة تشغيل الموقع والمجموعة
    Step 5 "إعادة تشغيل الموقع والمجموعة"
    try {
        Start-WebAppPool -Name $PoolName -ErrorAction Stop
        Ok "تم بدء مجموعة العمليات"
    } catch {
        Warn "تعذّرت إعادة تشغيل مجموعة العمليات: $_"
    }
    
    try {
        Start-Website -Name $SiteName -ErrorAction Stop
        Ok "تم بدء الموقع"
    } catch {
        Warn "تعذّرت إعادة تشغيل الموقع: $_"
    }
    
    Start-Sleep -Seconds 2
    
    # تسجيل الترقية
    Step 6 "تسجيل الترقية"
    $log = Join-Path $Target 'deploy.log'
    $logDir = Split-Path -Parent $log
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "$timestamp | $sha"
    Add-Content -LiteralPath $log -Value $entry -ErrorAction Continue
    Ok "تم تسجيل: $entry"
    
    Write-Host "`n✅ تمّ النشر بنجاح على $Target" -ForegroundColor Green
    
} catch {
    Write-Host "`n❌ خطأ أثناء النشر: $_" -ForegroundColor Red
    throw $_
    
} finally {
    # نظّف الملفات المؤقتة
    if (Test-Path $extract) {
        Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit 0
