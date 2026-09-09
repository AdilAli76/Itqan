# Kinetic ERP v1.6.6 - Production Deployment Fix Steps

**Date**: 2026-09-09  
**Issue**: Backend API not responding (500 errors) + HTTPS not configured  
**Status**: In Progress

---

## Current Situation

✅ **Working:**
- Frontend is accessible at http://erp.droob-albayan.ly (HTTP:80)
- wwwroot files are deployed correctly
- IIS site configuration is correct

❌ **Not Working:**
- Backend API returning 500 (HTTP://)
- SQL Server connectivity issue
- HTTPS:443 binding not configured

---

## Fix Plan

### Phase 1: Diagnose & Fix SQL Server Connectivity (15 min)

The backend API is unable to connect to SQL Server. Follow these steps:

1. **On Production Server (Windows), Open PowerShell as Administrator**

2. **Run Diagnostic Script:**
   ```powershell
   cd C:\kinetic
   # Save this script: diagnose-backend-api.ps1
   .\diagnose-backend-api.ps1
   ```

   This will show:
   - SQL Server service status
   - Network connectivity to port 1433
   - Named instances available
   - Current connection string in appsettings.Production.json
   - IIS app pool status
   - Backend API health check results

3. **Analyze Results:**
   - If TCP port 1433 is NOT reachable → SQL Server doesn't have TCP/IP enabled
   - If API returns 500 → Connection string is incorrect or SQL Server is not running

4. **If TCP is not working, run Fix Script:**
   ```powershell
   cd C:\kinetic
   # Save this script: fix-sql-connection.ps1
   .\fix-sql-connection.ps1
   ```

   This will:
   - Restart SQL Server service
   - Enable TCP/IP protocol
   - Update connection string
   - Recycle IIS app pool
   - Test API connectivity

5. **Expected Result:**
   - ✓ API responds with HTTP 200 OK
   - ✓ /api/health returns JSON health check data
   - ✓ Backend DLLs can connect to kinetic_erp database

---

### Phase 2: Configure HTTPS:443 Binding (10 min)

Once Backend API is working, set up secure HTTPS connection:

1. **On Production Server, Open PowerShell as Administrator**

2. **List Available SSL Certificates:**
   ```powershell
   Get-ChildItem -Path "Cert:\LocalMachine\My" | `
     Select-Object Subject, Thumbprint, NotAfter | `
     Format-Table -AutoSize
   ```

   Look for certificate with Subject containing: `erp.droob-albayan.ly` or `droob-albayan.ly`

3. **If certificate exists with correct domain:**
   - Note the **Thumbprint** value
   - Run HTTPS setup script

4. **If NO certificate exists:**
   - Contact IT/Admin for production SSL certificate for `erp.droob-albayan.ly`
   - OR generate self-signed certificate (for testing):
     ```powershell
     $cert = New-SelfSignedCertificate -DnsName "erp.droob-albayan.ly" `
       -CertStoreLocation "Cert:\LocalMachine\My" `
       -NotAfter (Get-Date).AddYears(1) `
       -FriendlyName "Kinetic ERP Production"
     $cert.Thumbprint
     ```

5. **Run HTTPS Setup Script:**
   ```powershell
   cd C:\kinetic
   # Save this script: add-https-binding.ps1
   .\add-https-binding.ps1
   ```

   This will:
   - List all available SSL certificates
   - Select the correct certificate for erp.droob-albayan.ly
   - Add HTTPS:443 binding to IIS site
   - Create HTTP→HTTPS redirect rule
   - Restart IIS
   - Test HTTPS connectivity

6. **Expected Result:**
   - ✓ HTTPS:443 binding appears in IIS site bindings
   - ✓ https://erp.droob-albayan.ly is accessible
   - ✓ http://erp.droob-albayan.ly redirects to https://erp.droob-albayan.ly

---

## Quick Commands Reference

### Check SQL Server Status
```powershell
Get-Service MSSQL$SQLEXPRESS | Select-Object Status
Get-Service MSSQLSERVER | Select-Object Status
```

### Test SQL Connection
```powershell
sqlcmd -S "(local)" -Q "SELECT @@VERSION" -E
sqlcmd -S ".\SQLEXPRESS" -Q "SELECT DB_ID('kinetic_erp')" -E
```

### View IIS Site Configuration
```powershell
Get-IISSite -Name "Kinetic" | Format-Table Name, State, Bindings -AutoSize
```

### Recycle App Pool
```powershell
iisreset /recycle /apppool:Kinetic
```

### Test Backend API
```powershell
Invoke-WebRequest -Uri "http://localhost/api/health" -Method Get
Invoke-WebRequest -Uri "https://localhost/api/health" -Method Get -SkipCertificateCheck
```

### View IIS Logs
```powershell
Get-ChildItem "C:\inetpub\logs\LogFiles" -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 5
Get-Content "C:\inetpub\logs\LogFiles\W3SVC1\u_ex260909.log" | Select-String "500"
```

---

## Troubleshooting

### Issue: "Named Pipes Provider: Could not open a connection"
**Cause:** Named pipes protocol is not enabled or TCP/IP is misconfigured

**Solution:**
1. Open SQL Server Configuration Manager (SQL Server 2019+)
2. Navigate: SQL Server Services → Right-click SQL Server instance
3. Enable: Named Pipes + TCP/IP protocols
4. Restart SQL Server service
5. Test with: `sqlcmd -S "." -Q "SELECT 1" -E`

### Issue: "API returning HTML index.html instead of JSON"
**Cause:** Request is hitting the static file handler, not the API route

**Solution:**
1. Verify IIS site physical path is: `C:\kinetic\` (not `C:\kinetic\backend\`)
2. Verify backend DLLs exist: `C:\kinetic\KineticEnterprise.Api.dll`
3. Check IIS logs for routing errors
4. Restart app pool: `iisreset /recycle /apppool:Kinetic`

### Issue: "Connection refused on port 1433"
**Cause:** SQL Server not listening on TCP port 1433

**Solution:**
1. Check if port is listening:
   ```powershell
   netstat -ano | findstr "1433"
   ```
2. If not found, enable TCP/IP in SQL Server Configuration Manager
3. Verify SQL Server service is running
4. Restart SQL Server

### Issue: "HTTPS binding won't add - certificate error"
**Cause:** Certificate thumbprint is invalid or certificate doesn't have private key

**Solution:**
1. Verify certificate exists:
   ```powershell
   Get-ChildItem "Cert:\LocalMachine\My" | Where-Object { $_.Thumbprint -eq "YOUR-THUMBPRINT" }
   ```
2. Verify certificate has private key:
   ```powershell
   Get-ChildItem "Cert:\LocalMachine\My" | Where-Object { $_.HasPrivateKey }
   ```
3. If certificate is missing, import from PFX file or generate new one

---

## Verification Checklist

After running both fix scripts:

- [ ] SQL Server service is running
- [ ] TCP/IP protocol is enabled for SQL Server
- [ ] Backend API responds to http://localhost/api/health with 200 OK
- [ ] Connection string in appsettings.Production.json is correct
- [ ] IIS app pool "Kinetic" is started
- [ ] HTTPS:443 binding exists on Kinetic site
- [ ] SSL certificate is valid for erp.droob-albayan.ly
- [ ] https://erp.droob-albayan.ly is accessible
- [ ] http://erp.droob-albayan.ly redirects to https://
- [ ] Browser shows valid/secure connection (HTTPS ✓)
- [ ] All 7 features of v1.6.6 are working

---

## Next Steps After Fix

Once both issues are resolved (API responding + HTTPS working):

1. **Test All Features** (per DEPLOYMENT_CHECKLIST_V1.6.6.md):
   - Customer Tags
   - Print Control Toggle
   - Monthly Deductions
   - Category Field
   - Enhanced POS
   - Print System
   - Customer Dashboard

2. **Performance Testing**:
   - Check response times
   - Monitor database queries
   - Verify caching works (print logo caching)

3. **Security Verification**:
   - SSL/TLS certificate validity
   - API authentication with Passkeys
   - Database connection security

4. **Documentation**:
   - Document final configuration
   - Update deployment logs
   - Record any custom settings

---

## Script Files Location

All scripts are saved to your scratchpad:
- `diagnose-backend-api.ps1` - Diagnostic script
- `fix-sql-connection.ps1` - SQL Server connection fix
- `add-https-binding.ps1` - HTTPS binding setup
- `PRODUCTION_FIX_STEPS.md` - This guide

**To download scripts:**
1. Open this session in claude.ai/code
2. Go to Scratchpad folder
3. Download each .ps1 file
4. Copy to your production server
5. Run as Administrator

---

## Status Summary

| Component | Status | Action |
|-----------|--------|--------|
| Frontend (HTTP:80) | ✅ Working | No action needed |
| Backend API (HTTP) | ❌ 500 Error | Run fix-sql-connection.ps1 |
| SQL Server | ⚠️ Connectivity Issue | Run fix-sql-connection.ps1 |
| HTTPS:443 | ❌ Not Configured | Run add-https-binding.ps1 |
| v1.6.6 Features | ⏳ Pending API | Test after API fix |

---

**Estimated Fix Time:** 30-45 minutes total  
**Complexity:** Medium (requires PowerShell & IIS knowledge)  
**Risk Level:** Low (all changes are reversible)

Contact your IT/System Administrator if you need help with any step.
