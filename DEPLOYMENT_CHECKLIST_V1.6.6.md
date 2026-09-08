# Kinetic ERP v1.6.6 - Complete Deployment Checklist

**Status**: Ready for Production Deployment
**All Implementation**: COMPLETE
**Testing**: Use staging environment first

---

## 🚀 QUICK START

```bash
# 1. Build everything (runs on Windows)
.\build-v1.6.6.ps1

# This creates: kinetic_pkg_YYYY-MM-DD_HHMM.zip (~50-100 MB)

# 2. Transfer ZIP to server
Copy-Item .\kinetic_pkg_*.zip \\SERVER\c$\publish\

# 3. On server, extract and deploy
cd C:\publish
Expand-Archive kinetic_pkg_*.zip -DestinationPath .\extracted
cd .\extracted\1.6.6

# 4. Apply database migration
sqlcmd -S . -U sa -P PASSWORD -d kinetic_erp -i MIGRATIONS_1.6.6.sql

# 5. Deploy files (stop IIS first)
iisreset /stop
robocopy . C:\kinetic\ /MIR
iisreset /start

# 6. Verify
curl https://kinetic-erp.example.com/api/health
```

---

## 📋 PRE-DEPLOYMENT VERIFICATION

### Local Machine (Before Building)

- [ ] Git branch is `claude/comprehensive-features-1.6.6`
- [ ] All changes committed (`git status` shows clean)
- [ ] Flutter SDK installed and updated
- [ ] .NET 8.0 SDK installed and updated
- [ ] Node.js 18+ installed (for web assets)
- [ ] PowerShell 5.0+ available
- [ ] 10+ GB free disk space

### Verify Code Quality

```bash
# Check Dart analysis
dart analyze

# Run Flutter tests (if available)
flutter test

# Check backend (on local machine with .NET)
cd backend/KineticEnterprise.Api
dotnet build --configuration Release
```

---

## 🏗️ STEP 1: BUILD PHASE (30-45 minutes)

### Option A: Automated Build (Recommended)

```powershell
# From project root
cd C:\kinetic-erp

# Run full build script
.\build-v1.6.6.ps1

# Output: kinetic_pkg_2026-09-08_0230.zip (~80 MB)
# Contains:
#   - Backend binaries
#   - Frontend web build
#   - Desktop (Windows) build
#   - Database migration SQL
#   - Deployment scripts
#   - Hash file for verification
```

### Option B: Manual Build Steps

```bash
# 1. Build Backend
cd backend/KineticEnterprise.Api
dotnet restore
dotnet build --configuration Release
dotnet publish --configuration Release --output ../../bin/publish/backend

# 2. Build Frontend
cd ../../
flutter pub get
flutter build web --release --build-name=1.6.6 --build-number=1660
flutter build windows --release  # Optional

# 3. Package Everything
mkdir -p build/package/1.6.6
cp -r bin/publish/backend/* build/package/1.6.6/
cp -r build/web build/package/1.6.6/wwwroot
cp docs/MIGRATIONS_1.6.6.sql build/package/1.6.6/
cp tool/deploy-now.ps1 build/package/1.6.6/
cd build/package
zip -r kinetic_pkg_$(date +%Y-%m-%d_%H%M).zip 1.6.6/
```

### Verify Package

```powershell
# Verify file exists and size is reasonable
Get-Item .\kinetic_pkg_*.zip | Select-Object Name, Length

# Verify SHA256 hash
Get-FileHash .\kinetic_pkg_*.zip -Algorithm SHA256 | Select-Object Hash

# List contents
Expand-Archive .\kinetic_pkg_*.zip -DestinationPath .\test-extract
Get-ChildItem .\test-extract\1.6.6\
```

---

## 🗄️ STEP 2: DATABASE MIGRATION (5-10 minutes)

### Pre-Migration

```sql
-- ALWAYS BACKUP FIRST
BACKUP DATABASE kinetic_erp TO DISK = 'C:\Backups\kinetic_erp_pre_1.6.6.bak';

-- Verify existing tables don't conflict
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_NAME IN ('customer_tags', 'entitlement_deduction_schedules', 'print_audit_logs');

-- Should return: (empty - tables don't exist yet)
```

### Execute Migration

```powershell
# Method 1: Using sqlcmd (Recommended)
sqlcmd -S . -U sa -P YOUR_PASSWORD -d kinetic_erp -i C:\kinetic_pkg_extract\1.6.6\MIGRATIONS_1.6.6.sql

# Method 2: Using SQL Server Management Studio
# Open MIGRATIONS_1.6.6.sql
# Execute entire script

# Method 3: Using Entity Framework (if preferred)
# cd backend/KineticEnterprise.Api
# dotnet ef database update
```

### Post-Migration Verification

```sql
-- Verify all 3 tables created
SELECT COUNT(*) as TableCount FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_NAME IN ('customer_tags', 'entitlement_deduction_schedules', 'print_audit_logs');

-- Should return: 3

-- Verify indexes
SELECT TABLE_NAME, INDEX_NAME FROM INFORMATION_SCHEMA.STATISTICS
WHERE TABLE_NAME IN ('customer_tags', 'entitlement_deduction_schedules', 'print_audit_logs')
ORDER BY TABLE_NAME;

-- Verify foreign key constraints
SELECT * FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS
WHERE CONSTRAINT_NAME LIKE '%customer_tags%'
   OR CONSTRAINT_NAME LIKE '%entitlement%'
   OR CONSTRAINT_NAME LIKE '%print_audit%';

-- Check row counts (should be 0 initially)
SELECT 
  'customer_tags' as TableName, COUNT(*) as RowCount FROM customer_tags
UNION ALL
SELECT 'entitlement_deduction_schedules', COUNT(*) FROM entitlement_deduction_schedules
UNION ALL
SELECT 'print_audit_logs', COUNT(*) FROM print_audit_logs;

-- Should return: 0, 0, 0
```

---

## 💻 STEP 3: BACKEND DEPLOYMENT (10-15 minutes)

### Prepare Server

```powershell
# On deployment server
# 1. Stop IIS Application Pool
iisreset /stop

# 2. Create backup of current binaries
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
robocopy C:\kinetic\ "C:\kinetic_backup_$timestamp\" /MIR

# 3. Extract deployment package
$extractPath = "C:\kinetic_extract_$timestamp"
Expand-Archive C:\publish\kinetic_pkg_*.zip -DestinationPath $extractPath
```

### Deploy Backend

```powershell
# Copy backend files
robocopy "$extractPath\1.6.6\" C:\kinetic\ /MIR /XO /XD wwwroot desktop

# Verify files copied
Get-ChildItem C:\kinetic\*.dll | Measure-Object
```

### Restart Services

```powershell
# Restart IIS
iisreset /start

# Verify application pool running
Get-WebAppPoolState -Name "KineticERP"

# Should show: "Started"
```

---

## 🎨 STEP 4: FRONTEND DEPLOYMENT (5-10 minutes)

### Deploy Web Frontend

```powershell
# Option 1: Copy all web files (complete replacement)
robocopy "$extractPath\1.6.6\wwwroot\" C:\kinetic\wwwroot\ /MIR

# Option 2: Preserve custom configs (if needed)
robocopy "$extractPath\1.6.6\wwwroot\" C:\kinetic\wwwroot\ /MIR /XF web.config appsettings.*.json

# Verify files
Get-ChildItem C:\kinetic\wwwroot\*.html
Get-ChildItem C:\kinetic\wwwroot\assets\
```

### Deploy Desktop (Optional Windows)

```powershell
# If you want to distribute Windows desktop app
robocopy "$extractPath\1.6.6\desktop\" C:\kinetic_desktop\ /MIR
# Users can download from your distribution point
```

### Clear Browser Cache (Optional)

```powershell
# Clear IIS compression cache
Remove-Item "C:\inetpub\temp\IIS Temporary Compressed Files\*" -Recurse -Force
```

---

## ✅ STEP 5: VERIFICATION (15-20 minutes)

### API Endpoints

```powershell
# Test health endpoint
curl -Invoke-WebRequest https://kinetic-erp.example.com/api/health

# Test with authentication header (if required)
$headers = @{
    "Authorization" = "Bearer YOUR_TOKEN_HERE"
}
Invoke-WebRequest -Uri https://kinetic-erp.example.com/api/customers -Headers $headers
```

### Database Connectivity

```sql
-- Verify connection string works
-- Check in appsettings.json that connection string is correct

SELECT GETDATE() as ServerTime;
SELECT @@VERSION as SQLVersion;
```

### New Feature Tests (Quick)

```powershell
# 1. Customer Tags API
Invoke-WebRequest https://kinetic-erp.example.com/api/customer-tags/autocomplete -Headers $headers

# 2. Entitlement Deductions API  
Invoke-WebRequest https://kinetic-erp.example.com/api/entitlement-deduction-schedules -Headers $headers

# 3. Print Audit Logs
SELECT COUNT(*) as PrintCount FROM print_audit_logs;
```

### Application Logs

```powershell
# Check for errors in application logs
Get-EventLog -LogName "Application" -Source "IIS AspNetCore" -Newest 20

# Check for EntitlementDeduction scheduled job start
# Should see log entry about service starting
Get-EventLog -LogName "Application" | Where-Object { $_.Message -like "*Entitlement*" }
```

---

## 🧪 STEP 6: COMPREHENSIVE TESTING (2-3 hours)

### Recommended Testing Order

#### Test 1: Customer Tags (30 min)

```
UI Test:
1. Open Customers screen
2. Click "إضافة عميل جديد"
3. Add customer tags:
   - Type "VIP" → click tag
   - Type "Wholesale" → click tag
   - See tags appear as chips
4. Click "حفظ"
5. Verify tags saved (reload page)
6. Edit customer → verify tags loaded
7. Delete tag → verify removed
8. Test duplicate prevention

API Test:
- GET /customer-tags/customer/{id} → verify tags listed
- POST /customer-tags → add new tag
- DELETE /customer-tags/{tagId} → remove tag
- GET /customer-tags/autocomplete → verify all tags
```

#### Test 2: Print Control (30 min)

```
UI Test:
1. Open POS screen
2. Add items to cart
3. See "PrintControlToggle" above payment buttons:
   - Green "طباعة مفعّلة" (enabled)
4. Click toggle → turns orange "بدون طباعة"
5. Click "نقداً" (Cash) → checkout
6. Verify receipt NOT printed
7. Add new items
8. Click toggle → back to green
9. Checkout
10. Verify receipt IS printed

Function Test:
- 30-second timeout: Print large receipt, verify timeout works
- Error handling: Disconnect printer, verify error message in Arabic
- Audit logging: Check print_audit_logs table has entry
- Caching: Print twice quickly, verify 2nd is faster
```

#### Test 3: Entitlement Deductions (45 min)

```
Setup:
1. Create customer category (if needed)
2. Create entitlement customers in category
3. Create deduction schedule:
   - Category: [your category]
   - Amount: 100 د.ل
   - Day: today's day of month
   - Active: yes

Test:
1. Wait for 02:00 UTC or trigger manually (if available)
2. Check wallet transactions created
3. Verify each customer has transaction with:
   - kind = 'entitlement_deduction'
   - Amount matches schedule
4. Verify LastProcessedDate updated
5. Run again (same day) → verify no duplicate transactions
6. Test per-customer override:
   - Set customer EntitlementOverride = 50
   - Run deduction again
   - Verify transaction is 50, not 100

Database Checks:
SELECT * FROM entitlement_deduction_schedules;
SELECT * FROM customer_wallet_transactions WHERE kind = 'entitlement_deduction';
```

#### Test 4: Category Field (15 min)

```
UI Test:
1. Open Customers screen
2. Add/Edit customer
3. See "نموذج الحساب" dropdown
4. Select "استحقاق ممنوح" (Entitlement)
5. See category dropdown appear
6. Select category → saves

Database Test:
SELECT DISTINCT category_id FROM customers WHERE category_id IS NOT NULL;
```

#### Test 5: Performance - Print Caching (20 min)

```
Network Monitor:
1. Open browser developer tools (F12) → Network tab
2. Go to POS screen
3. Print receipt #1 → watch network calls
   - Should fetch logo and template
   - 3-4 network requests
4. Print receipt #2 → watch network calls
   - Should skip logo/template fetch
   - 1-2 network requests only

Performance:
- Receipt #1 print: ~3-5 seconds
- Receipt #2 print: ~1-2 seconds (cached)
```

---

## 🔍 ROLLBACK PLAN

### If Issues Found on Staging

```powershell
# 1. Stop IIS
iisreset /stop

# 2. Restore from backup (from deployment server backup we made earlier)
$timestamp = "YYYYMMDD_HHMM"  # Use timestamp from your backup
robocopy "C:\kinetic_backup_$timestamp\" C:\kinetic\ /MIR

# 3. Restore database (if migration caused issues)
RESTORE DATABASE kinetic_erp FROM DISK = 'C:\Backups\kinetic_erp_pre_1.6.6.bak'
GO
-- Wait for restore to complete

# 4. Restart IIS
iisreset /start

# 5. Verify
curl https://kinetic-erp.example.com/api/health
```

### If Production Issues Found

```sql
-- Drop new tables (reverting migration)
-- WARNING: This will delete all data in these tables!
DROP TABLE [dbo].[print_audit_logs];
DROP TABLE [dbo].[entitlement_deduction_schedules];
DROP TABLE [dbo].[customer_tags];
GO
```

---

## 📊 MONITORING POST-DEPLOYMENT

### Check Scheduled Job

```powershell
# Verify EntitlementDeductionHostedService logs
Get-EventLog -LogName "Application" -Source "KineticERP" | 
  Where-Object { $_.Message -like "*Entitlement*" } | 
  Format-List TimeGenerated, Message | 
  Head -10

# Should see:
# TimeGenerated: [Today at 02:00]
# Message: "בدء تشغيل الخصم الشهري المجدول" or similar
```

### Monitor Database Growth

```sql
-- Monitor print audit logs growth
SELECT COUNT(*) as PrintEventsCount FROM print_audit_logs;
SELECT DATE(created_at) as Date, COUNT(*) as Count 
FROM print_audit_logs 
GROUP BY DATE(created_at) 
ORDER BY Date DESC;

-- Archive old logs after 90 days (recommended)
DELETE FROM print_audit_logs 
WHERE created_at < DATEADD(DAY, -90, GETDATE());
```

### Performance Metrics

```sql
-- Customer tags autocomplete performance
SELECT TOP 10 DISTINCT tag_name 
FROM customer_tags 
WHERE organization_id = 'YOUR_ORG_ID'
ORDER BY tag_name;

-- Should execute in < 500ms

-- Active deduction schedules
SELECT COUNT(*) as ActiveSchedules 
FROM entitlement_deduction_schedules 
WHERE is_active = 1;
```

---

## 📞 SUPPORT & DOCUMENTATION

### Reference Files

- `docs/MIGRATIONS_1.6.6.sql` - Database migration
- `docs/V1.6.6_MIGRATION_GUIDE.md` - Complete guide
- `docs/V1.6.6_IMPLEMENTATION_SUMMARY.md` - Feature details
- `docs/V1.6.6_FINAL_STATUS.md` - Current status
- `BUILD_V1.6.6.md` - Build instructions
- `build-v1.6.6.ps1` - Build script

### Troubleshooting

**Database Migration Failed**
- Check if tables already exist
- Verify SQL Server 2019+ with proper permissions
- Check foreign key constraints don't conflict

**Print Toggle Not Visible**
- Rebuild Flutter: `flutter clean && flutter pub get && flutter build web`
- Clear browser cache (Ctrl+Shift+Del)
- Check browser console (F12) for errors

**Deductions Not Processing**
- Check server time is correct (UTC)
- Verify EntitlementDeductionHostedService running
- Check database for schedules with today's day_of_month
- Review application logs for errors

**Timeout on Print**
- Verify network connectivity to printer
- Check printer status and queue
- Review print error messages in Arabic

---

## ✨ SUCCESS CRITERIA

All features working when:
- [ ] Customers can add/remove tags with autocomplete
- [ ] Customer tags persist after save and load on edit
- [ ] Print control toggle visible in POS
- [ ] Skip printing when toggle disabled
- [ ] Receipt prints when toggle enabled
- [ ] Print timeout enforces 30-second limit
- [ ] Logo cached (2nd print faster than 1st)
- [ ] Print audit logs recorded in database
- [ ] Deduction schedules can be created/edited
- [ ] Monthly deductions run automatically at 02:00 UTC
- [ ] Wallet transactions created for deductions
- [ ] Per-customer override amount works

---

## 🎉 FINAL NOTES

**Total Deployment Time**: 2-3 hours (including testing)

**Estimated Timeline**:
- Build: 30-45 min
- Database Migration: 5-10 min  
- Backend Deploy: 10-15 min
- Frontend Deploy: 5-10 min
- Verification: 15-20 min
- Testing: 2-3 hours (parallel with other tasks)
- **Total: 3-5 hours**

**Go-Live Checklist**:
- [ ] All tests passed
- [ ] Performance verified
- [ ] Backup confirmed working
- [ ] Team trained on new features
- [ ] Documentation shared
- [ ] Support team on standby
- [ ] Database backups recent
- [ ] Rollback plan documented

---

**Status**: ✅ Ready for Deployment
**Version**: v1.6.6
**Release Date**: 2026-09-09
