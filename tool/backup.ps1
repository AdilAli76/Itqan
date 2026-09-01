<#
.SYNOPSIS
    نسخة احتياطية من قاعدة بيانات Kinetic Enterprise، مع تحقّق واستبقاء.

.DESCRIPTION
    قاعدة واحدة تخدم كل عملائك؛ فقدانها فقدانهم جميعاً. لذلك لا يكتفي
    السكربت بأخذ النسخة:

      - يتحقّق من سلامتها بـ RESTORE VERIFYONLY. النسخة غير المتحقَّق منها
        وعدٌ لا ضمان: أعطال القرص تُكتشف عند الاسترجاع لا عند الأخذ، أي في
        أسوأ لحظة ممكنة.
      - يحذف النسخ الأقدم من [RetentionDays] بعد نجاح الجديدة لا قبلها،
        فلا يمرّ النظام بلحظة واحدة بلا نسخة صالحة.
      - يكتب سجلاً بكل عملية، لأن نسخة احتياطية توقّفت صامتةً قبل شهر هي
        الحالة الشائعة لا النادرة.

    SQL Server Express لا يملك SQL Server Agent، فالجدولة عبر Task
    Scheduler — راجع المعامل -Install أدناه.

.PARAMETER SqlInstance
    نسخة SQL Server. الافتراضي .\SQLEXPRESS — نفس افتراض server_setup.ps1.

    اختلاف الافتراض بين السكربتين كان يُنتج أسوأ أنواع الفشل: التسجيل
    ينجح والنسخة تفشل كل ليلة على نسخة SQL خاطئة، فلا يُكتشف إلا يوم
    الحاجة إلى الاسترجاع.

.PARAMETER Database
    اسم القاعدة. الافتراضي KineticEnterprise

.PARAMETER Path
    مجلد النسخ. الافتراضي D:\Backups\Kinetic أو C:\Backups\Kinetic إن لم
    يوجد قرص D.

.PARAMETER RetentionDays
    عمر الاستبقاء بالأيام. الافتراضي 30.

.PARAMETER Install
    يُسجّل مهمة يومية في Task Scheduler بدل أخذ نسخة الآن.

.PARAMETER Time
    توقيت المهمة اليومية مع -Install. الافتراضي 02:00.

.EXAMPLE
    .\tool\backup.ps1
    .\tool\backup.ps1 -Install -Time 03:30
#>
[CmdletBinding()]
param(
    [string]$SqlInstance = '.\SQLEXPRESS',
    [string]$Database = 'KineticEnterprise',
    [string]$Path,
    <#
      يأخذ النسخة بلا RESTORE VERIFYONLY.

      **لا يُمرَّر إلا عن قصد.** نسخةٌ غير متحقَّق منها وعدٌ لا ضمان: أعطال
      القرص تُكتشف عند الاسترجاع لا عند الأخذ — أي في أسوأ لحظة ممكنة.

      وسببه الوحيد المشروع: حسابٌ يملك النسخ ولا يملك CREATE DATABASE التي
      يطلبها VERIFYONLY، ولا تريد منحها. والأصوب منحُها — راجع الرسالة التي
      يطبعها السكربت عند فشل التحقّق.
    #>
    [switch]$SkipVerify,
    # مجلد المرفقات المرفوعة (Storage:Path في appsettings.Production.json).
    # يُشتقّ من ملف الأسرار إن تُرك فارغاً.
    [string]$UploadsPath,
    [int]$RetentionDays = 30,
    [switch]$Install,
    [string]$Time = '02:00'
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

if (-not $Path) {
    $Path = if (Test-Path 'D:\') { 'D:\Backups\Kinetic' } else { 'C:\Backups\Kinetic' }
}
$logFile = Join-Path $Path 'backup.log'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host "    $Message" -ForegroundColor $(if ($Level -eq 'ERROR') { 'Red' } elseif ($Level -eq 'WARN') { 'Yellow' } else { 'Green' })
    if (Test-Path $Path) { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 }
}

function Invoke-Sql {
    param([string]$Query, [int]$TimeoutSec = 3600)
    $conn = New-Object System.Data.SqlClient.SqlConnection(
        "Server=$SqlInstance;Database=master;Integrated Security=true;TrustServerCertificate=true;Connection Timeout=15")
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = $TimeoutSec
        [void]$cmd.ExecuteNonQuery()
    } finally { $conn.Close() }
}

# ═══════════════════ تسجيل المهمة المجدوَلة ═══════════════════════════════
if ($Install) {
    Write-Host "`n=== تسجيل مهمة النسخ الاحتياطي اليومية ===" -ForegroundColor White

    # يتطلّب صلاحيات مسؤول: المهام على مستوى النظام لا تُسجَّل بحساب عادي.
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw 'شغّل PowerShell كمسؤول لتسجيل المهمة.'
    }

    $script = $MyInvocation.MyCommand.Path
    $taskName = "KineticBackup_$Database"

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -SqlInstance `"$SqlInstance`" -Database `"$Database`" -Path `"$Path`" -RetentionDays $RetentionDays"
    $trigger = New-ScheduledTaskTrigger -Daily -At $Time
    # SYSTEM لا حساب المستخدم: المهمة يجب أن تعمل والسيرفر بلا جلسة مفتوحة.
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd `
        -ExecutionTimeLimit (New-TimeSpan -Hours 4)

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null

    Write-Host "    سُجّلت المهمة '$taskName' يومياً الساعة $Time" -ForegroundColor Green
    Write-Host "    الوجهة: $Path" -ForegroundColor Gray
    Write-Host ''
    Write-Host '    تبقى خطوة لا يستطيع سكربت فعلها عنك:' -ForegroundColor Yellow
    Write-Host '    انسخ مجلد النسخ إلى خارج السيرفر دورياً (قرص خارجي أو تخزين سحابي).' -ForegroundColor Yellow
    Write-Host '    نسخة احتياطية على القرص نفسه لا تحمي من فقدان الجهاز ولا من فدية.' -ForegroundColor Yellow
    return
}

# ═══════════════════ أخذ النسخة ═══════════════════════════════════════════
Write-Host "`n=== نسخة احتياطية: $Database ===" -ForegroundColor White

if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

# صلاحية الكتابة تخصّ حساب خدمة SQL Server لا المستخدم الذي يشغّل السكربت:
# BACKUP ينفّذه محرّك القاعدة بهويته هو. هذا أشيع سبب لفشل أول نسخة، ورسالته
# الخام ("Operating system error 5") لا تقول ذلك. نمنح الصلاحية استباقياً
# متى أمكن بدل انتظار الفشل.
$instanceName = if ($SqlInstance.Contains('\')) { $SqlInstance.Split('\')[-1] } else { '' }
$serviceName = if ($instanceName) { 'MSSQL$' + $instanceName } else { 'MSSQLSERVER' }
try {
    $account = (Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop).StartName
    if ($account) {
        $acl = Get-Acl -LiteralPath $Path
        $shortName = $account.Split('\')[-1]
        $has = $acl.Access | Where-Object { $_.IdentityReference.Value -like "*$shortName*" }
        if (-not $has) {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $account, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
            Set-Acl -LiteralPath $Path -AclObject $acl
            Write-Log "مُنح $account صلاحية الكتابة في مجلد النسخ"
        }
    }
} catch {
    # الفشل هنا غير قاتل: قد لا نملك صلاحية تعديل ACL، وقد تكون ممنوحة
    # أصلاً. النسخ أدناه هو الحكم الفعلي.
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$file = Join-Path $Path "$Database`_$stamp.bak"

try {
    Write-Log "بدء النسخ إلى $file"

    # COMPRESSION غير مدعوم في Express — نحاول بها ونسقط إلى بلا ضغط.
    # الفرق كبير (نحو 80% أصغر) فيستحق المحاولة لا التخلّي المسبق.
    $withCompression = @"
BACKUP DATABASE [$Database] TO DISK = N'$file'
WITH FORMAT, INIT, COMPRESSION, CHECKSUM, STATS = 25,
     NAME = N'$Database كامل';
"@
    try {
        Invoke-Sql -Query $withCompression
        Write-Log 'أُخذت النسخة (مضغوطة)'
    } catch {
        if ($_.Exception.Message -match 'COMPRESSION|compression') {
            Write-Log 'الضغط غير مدعوم في هذه النسخة — نسخ بلا ضغط' 'WARN'
            Invoke-Sql -Query @"
BACKUP DATABASE [$Database] TO DISK = N'$file'
WITH FORMAT, INIT, CHECKSUM, STATS = 25, NAME = N'$Database كامل';
"@
            Write-Log 'أُخذت النسخة (بلا ضغط)'
        } else { throw }
    }

    # ── التحقّق: في try خاصّ به ─────────────────────────────────────────
    #
    # **العطب الذي يصلحه هذا الفصل:** كان التحقّق داخل try النسخ نفسه،
    # وcatch يحذف الملف. فحين عجز التحقّق عن **العمل** — لا حين وجد
    # فساداً — حُذفت نسخةٌ سليمة أُخذت للتوّ، وتوقّف النشر. أي أن العميل
    # بقي بلا نسخة **وبلا ترقية** معاً، والسبب صلاحيةٌ ناقصة لا قرصٌ تالف.
    #
    # وهو نفس مصيدة هذا المشروع مقلوبةً: خطأٌ يصف **تعذّر الفحص** عومل
    # معاملة **فشل الفحص**.
    $sizeMb = [math]::Round((Get-Item $file).Length / 1MB, 1)

    if ($SkipVerify) {
        Write-Log "تُخطّي التحقّق بطلبٍ صريح — النسخة غير متحقَّق منها ($sizeMb ميغابايت)" 'WARN'
    } else {
        # CHECKSUM أعلاه يكتب مجاميع تحقّق، وهذا يقرأها كلها.
        Write-Log 'التحقّق من سلامة النسخة…'
        try {
            Invoke-Sql -Query "RESTORE VERIFYONLY FROM DISK = N'$file' WITH CHECKSUM;"
            Write-Log "النسخة سليمة ($sizeMb ميغابايت)"
        } catch {
            $vmsg = $_.Exception.Message

            # RESTORE VERIFYONLY يتطلّب صلاحية CREATE DATABASE — وهذا غير
            # بديهي: الأمر لا يُنشئ قاعدة ولا يكتب شيئاً، لكنه يُصنَّف مع
            # عائلة RESTORE كلّها. فحسابٌ يملك النسخ ولا يملكها يأخذ النسخة
            # بنجاح ثم يعجز عن قراءتها.
            if ($vmsg -match 'CREATE DATABASE permission denied') {
                $who = try { [Security.Principal.WindowsIdentity]::GetCurrent().Name } catch { '(تعذّرت قراءته)' }
                Write-Log 'تعذّر التحقّق — لا فسادَ في النسخة بل صلاحية ناقصة.' 'ERROR'
                Write-Log "النسخة أُخذت وهي محفوظة: $file ($sizeMb ميغابايت)" 'WARN'
                Write-Log "الحساب المتصل: $who" 'ERROR'
                Write-Log 'RESTORE VERIFYONLY يتطلّب CREATE DATABASE وإن لم يُنشئ شيئاً.' 'ERROR'
                Write-Log 'الحل — نفّذه مرّة واحدة على الخادم بحساب مسؤول:' 'ERROR'
                Write-Log "  sqlcmd -S $SqlInstance -E -Q `"GRANT CREATE ANY DATABASE TO [$who];`"" 'ERROR'
                Write-Log 'أو مرّر -SkipVerify لتأخذ نسخةً بلا تحقّق عن قصد.' 'ERROR'
            } else {
                Write-Log "فشل التحقّق: $vmsg" 'ERROR'
                # هنا وحده يُحذف الملف: التحقّق **عمل** ووجد فساداً. وملف
                # .bak تالف أخطر من غيابه لأنه يُحتسب نسخةً حتى تُجرَّب
                # ساعةَ الحاجة.
                if (Test-Path $file) { Remove-Item $file -Force -ErrorAction SilentlyContinue }
            }
            exit 1
        }
    }

} catch {
    $msg = $_.Exception.Message
    if ($msg -match 'Operating system error 5|Access is denied|Cannot open backup device') {
        Write-Log 'فشل النسخ: حساب خدمة SQL Server لا يملك الكتابة في مجلد النسخ.' 'ERROR'
        Write-Log "الحساب: $serviceName" 'ERROR'
        Write-Log 'الحل: شغّل السكربت كمسؤول (يمنح الصلاحية تلقائياً)،' 'ERROR'
        Write-Log 'أو اختر مساراً على قرص محلي يملكه الحساب — لا مجلد مستخدم ولا مشاركة شبكية.' 'ERROR'
    } else {
        Write-Log "فشل النسخ: $msg" 'ERROR'
    }
    # النسخة الفاشلة تُحذف: ملف .bak تالف في مجلد النسخ أخطر من غيابه،
    # لأنه يُحتسب نسخةً موجودة حتى تُجرَّب ساعةَ الحاجة.
    #
    # وهذا الحذف يخصّ فشل **النسخ** وحده الآن — تعذّرُ التحقّق يُعالَج
    # أعلاه ويُبقي الملف.
    if (Test-Path $file) { Remove-Item $file -Force -ErrorAction SilentlyContinue }
    exit 1
}

# ═══════════════════ المرفقات ════════════════════════════════════════════
#
# نسخة القاعدة وحدها **لا تكفي**: صفوف attachments تشير إلى ملفات على القرص،
# فاسترجاع القاعدة بلا الملفات يُنتج نظاماً يعرض مرفقات لا تُفتح — وهو أسوأ
# من فقدانها، لأن المستخدم يظنّها موجودة.
#
# والملفات مقسَّمة بمجلد لكل منظمة (راجع FilesController.OrgFolder)، فنسخة
# المرفقات قابلة للتجزئة: يمكن استرجاع عميل واحد بلا لمس بقيّة العملاء.

if (-not $UploadsPath) {
    # من ملف أسرار النشر: هو المصدر الوحيد الذي لا يكذب عن المجلد المستعمل.
    $secretsCandidates = @(
        'C:\kinetic\backend\appsettings.Production.json',
        'C:\inetpub\kinetic-api\appsettings.Production.json'
    ) | Where-Object { Test-Path $_ }

    if ($secretsCandidates) {
        try {
            $cfg = Get-Content $secretsCandidates[0] -Raw | ConvertFrom-Json
            if ($cfg.Storage -and $cfg.Storage.Path) { $UploadsPath = $cfg.Storage.Path }
        } catch { }
    }
}

if ($UploadsPath -and (Test-Path $UploadsPath)) {
    $uploadsZip = Join-Path $Path ("uploads_{0}.zip" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    try {
        Compress-Archive -Path (Join-Path $UploadsPath '*') -DestinationPath $uploadsZip -Force -ErrorAction Stop
        $sizeMb = [math]::Round((Get-Item $uploadsZip).Length / 1MB, 1)
        Write-Log "نُسخت المرفقات: $uploadsZip ($sizeMb ميغابايت)"
    } catch {
        # فشل المرفقات لا يُبطل نسخة القاعدة الناجحة — يُسجَّل بوضوح ويُكمَل.
        Write-Log "تعذّر نسخ المرفقات من $UploadsPath : $($_.Exception.Message)" 'WARN'
    }
}
elseif ($UploadsPath) {
    Write-Log "مجلد المرفقات غير موجود: $UploadsPath" 'WARN'
}
else {
    Write-Log 'لم يُحدَّد مجلد المرفقات — نسخة القاعدة وحدها. مرّر -UploadsPath' 'WARN'
}

# ═══════════════════ الاستبقاء ═══════════════════════════════════════════
# بعد نجاح الجديدة لا قبلها.
$cutoff = (Get-Date).AddDays(-$RetentionDays)
$old = Get-ChildItem -Path $Path -Filter "$Database`_*.bak" |
       Where-Object { $_.LastWriteTime -lt $cutoff }

if ($old) {
    # حارس: لا تُحذف كل النسخ مهما بلغ عمرها. ساعة نظام خاطئة أو توقّف
    # المهمة شهرين يجعل «كل النسخ قديمة» — والحذف حينها يمحو آخر ما تبقّى.
    $remaining = (Get-ChildItem -Path $Path -Filter "$Database`_*.bak").Count - $old.Count
    if ($remaining -lt 1) {
        Write-Log "تُرك $($old.Count) ملفاً قديماً: حذفها يعني بقاء صفر نسخ" 'WARN'
    } else {
        foreach ($f in $old) {
            Remove-Item $f.FullName -Force
            Write-Log "حُذفت نسخة قديمة: $($f.Name)"
        }
    }
}

# نفس الاستبقاء على أرشيفات المرفقات، وبنفس الحارس: لا تُحذف كلها.
$oldUploads = Get-ChildItem -Path $Path -Filter 'uploads_*.zip' -ErrorAction SilentlyContinue |
              Where-Object { $_.LastWriteTime -lt $cutoff }
if ($oldUploads) {
    $remainingUploads = (Get-ChildItem -Path $Path -Filter 'uploads_*.zip').Count - $oldUploads.Count
    if ($remainingUploads -lt 1) {
        Write-Log "تُرك $($oldUploads.Count) أرشيف مرفقات قديماً: حذفها يعني بقاء صفر" 'WARN'
    } else {
        foreach ($f in $oldUploads) { Remove-Item $f.FullName -Force }
        Write-Log "حُذف $($oldUploads.Count) أرشيف مرفقات قديم"
    }
}

$count = (Get-ChildItem -Path $Path -Filter "$Database`_*.bak").Count
$uploadCount = (Get-ChildItem -Path $Path -Filter 'uploads_*.zip' -ErrorAction SilentlyContinue).Count
Write-Log "اكتمل. نسخ القاعدة: $count — أرشيفات المرفقات: $uploadCount"
Write-Host ''

# رمز خروجٍ صريح عند النجاح.
#
# بدونه يبقى $LASTEXITCODE عند مُستدعي هذا السكربت على قيمته السابقة —
# PowerShell لا يضبطه إلا لأمرٍ أصليّ أو لـ`exit` صريح. فمن يقيس نتيجتنا
# به يقرأ رقماً لا علاقة له بنا، وقد وقع: نسخةٌ ناجحة تماماً أوقفت نشرةَ
# إنتاج بدعوى الفشل.
#
# والمُستدعي يُصفّره أيضاً قبل النداء (راجع ci_deploy.ps1) — حزامان لأن
# النسخة المثبَّتة على خادم العميل قد تكون أقدم من هذا السطر.
exit 0
