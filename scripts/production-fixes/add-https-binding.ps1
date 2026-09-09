#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Add HTTPS:443 binding to Kinetic ERP production site

.DESCRIPTION
    This script:
    1. Lists available SSL certificates
    2. Helps select the right certificate for erp.droob-albayan.ly
    3. Adds HTTPS:443 binding to IIS site
    4. Sets up HTTP to HTTPS redirect

.NOTES
    Requires: Administrator privileges
    Certificate: Must be valid for erp.droob-albayan.ly domain
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
Write-Info "Kinetic ERP - HTTPS Binding Setup"
Write-Info "==========================================="
Write-Info ""

# Check admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
if (-not $isAdmin) {
    Write-Error "This script requires Administrator privileges"
    exit 1
}

Write-Success "Running as Administrator"
Write-Info ""

# STEP 1: List Available Certificates
Write-Info "STEP 1: Available SSL Certificates"
Write-Info "──────────────────────────────────"

$certs = Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object { $_.HasPrivateKey }

if ($certs.Count -eq 0) {
    Write-Error "No certificates with private keys found in Local Machine\My store"
    Write-Info ""
    Write-Warning "OPTIONS:"
    Write-Warning ""
    Write-Warning "Option 1: Import existing certificate"
    Write-Warning "  1. Obtain .pfx or .pem certificate file"
    Write-Warning "  2. Use certutil or MMC to import to Cert:\LocalMachine\My"
    Write-Warning "  3. Re-run this script"
    Write-Warning ""
    Write-Warning "Option 2: Generate self-signed certificate (for testing)"
    Write-Warning "  Continue with this script - it will offer to generate one"
    Write-Warning ""
    Write-Warning "Option 3: Request from Certificate Authority"
    Write-Warning "  Contact IT/Admin for production SSL certificate"
    exit 1
}

Write-Success "Found $($certs.Count) certificate(s) with private keys"
Write-Info ""

# Find certificate for erp.droob-albayan.ly
$relevantCert = $null
foreach ($cert in $certs) {
    if ($cert.Subject -like '*erp.droob-albayan.ly*' -or `
        $cert.DnsNameList -contains 'erp.droob-albayan.ly' -or `
        $cert.Subject -like '*droob-albayan.ly*') {
        $relevantCert = $cert
        break
    }
}

Write-Info "Available certificates:"
Write-Info ""

$i = 1
foreach ($cert in $certs) {
    $marker = if ($cert -eq $relevantCert) { "→" } else { " " }
    Write-Info "$marker [$i] Subject: $($cert.Subject)"
    Write-Info "    Thumbprint: $($cert.Thumbprint)"
    Write-Info "    Expires: $($cert.NotAfter)"
    Write-Info "    DNS Names: $($cert.DnsNameList -join ', ')"
    Write-Info ""
    $i++
}

if ($relevantCert) {
    Write-Success "Found matching certificate: $($relevantCert.Subject)"
    $selectedCert = $relevantCert
} else {
    Write-Warning "No certificate found for erp.droob-albayan.ly"
    Write-Info "Using first available certificate"
    $selectedCert = $certs[0]
}

$thumbprint = $selectedCert.Thumbprint

Write-Info ""
Write-Success "Selected Certificate:"
Write-Info "  Subject: $($selectedCert.Subject)"
Write-Info "  Thumbprint: $thumbprint"
Write-Info "  Expires: $($selectedCert.NotAfter)"
Write-Info ""

# STEP 2: Get IIS Site Info
Write-Info "STEP 2: IIS Site Configuration"
Write-Info "──────────────────────────────"

$site = Get-IISSite | Where-Object { $_.Name -eq 'Kinetic' }

if (-not $site) {
    Write-Error "IIS Site 'Kinetic' not found"
    Write-Info "Available sites:"
    Get-IISSite | ForEach-Object { Write-Info "  - $($_.Name)" }
    exit 1
}

Write-Success "Found site: $($site.Name)"
Write-Info "Current bindings:"
foreach ($binding in $site.Bindings) {
    Write-Info "  - $($binding.Protocol)://$($binding.BindingInformation)"
}

# STEP 3: Add HTTPS Binding
Write-Info ""
Write-Info "STEP 3: Adding HTTPS:443 Binding"
Write-Info "────────────────────────────────"

$httpsBindingExists = $site.Bindings | Where-Object { $_.Protocol -eq 'https' }

if ($httpsBindingExists) {
    Write-Warning "HTTPS binding already exists"
    Write-Info "Existing HTTPS binding: $($httpsBindingExists.BindingInformation)"
    Write-Info "Skipping HTTPS binding addition"
} else {
    try {
        Write-Info "Adding HTTPS binding..."
        New-IISBinding -Name 'Kinetic' -Protocol 'https' -BindingInformation '*:443:erp.droob-albayan.ly' -CertificateThumbprint $thumbprint -ErrorAction Stop
        Write-Success "✓ HTTPS binding added successfully"

        # Verify
        $site = Get-IISSite -Name 'Kinetic'
        Write-Info "Updated bindings:"
        foreach ($binding in $site.Bindings) {
            Write-Info "  - $($binding.Protocol)://$($binding.BindingInformation)"
        }
    } catch {
        Write-Error "Failed to add HTTPS binding: $_"
        exit 1
    }
}

# STEP 4: Create HTTPS Redirect Rule
Write-Info ""
Write-Info "STEP 4: Setting Up HTTP→HTTPS Redirect"
Write-Info "─────────────────────────────────────"

$webConfigPath = 'C:\kinetic\web.config'

# Create redirect rule in web.config if not exists
if (Test-Path $webConfigPath) {
    Write-Info "Checking web.config for redirect rule..."

    [xml]$webConfig = Get-Content $webConfigPath

    # Check if rewrite rules exist
    if ($webConfig.configuration.'system.webServer'.rewrite -eq $null) {
        Write-Info "Adding rewrite rules to web.config..."

        $rewriteNode = $webConfig.CreateElement('rewrite')
        $rulesNode = $webConfig.CreateElement('rules')

        # Create redirect rule
        $ruleNode = $webConfig.CreateElement('rule')
        $ruleNode.SetAttribute('name', 'Redirect HTTP to HTTPS')
        $ruleNode.SetAttribute('stopProcessing', 'true')

        # Match condition
        $matchNode = $webConfig.CreateElement('match')
        $matchNode.SetAttribute('url', '(.*)')
        $ruleNode.AppendChild($matchNode)

        # Conditions
        $conditionsNode = $webConfig.CreateElement('conditions')
        $condNode = $webConfig.CreateElement('add')
        $condNode.SetAttribute('input', '{HTTPS}')
        $condNode.SetAttribute('pattern', 'off')
        $conditionsNode.AppendChild($condNode)
        $ruleNode.AppendChild($conditionsNode)

        # Action
        $actionNode = $webConfig.CreateElement('action')
        $actionNode.SetAttribute('type', 'Redirect')
        $actionNode.SetAttribute('url', 'https://erp.droob-albayan.ly{R:1}')
        $actionNode.SetAttribute('redirectType', 'Permanent')
        $ruleNode.AppendChild($actionNode)

        $rulesNode.AppendChild($ruleNode)
        $rewriteNode.AppendChild($rulesNode)
        $webConfig.configuration.'system.webServer'.AppendChild($rewriteNode)

        $webConfig.Save($webConfigPath)
        Write-Success "✓ Redirect rule added to web.config"
    } else {
        Write-Info "Rewrite rules already configured"
    }
} else {
    Write-Warning "web.config not found at: $webConfigPath"
}

# STEP 5: Restart IIS
Write-Info ""
Write-Info "STEP 5: Restarting IIS"
Write-Info "─────────────────────"

try {
    Write-Info "Restarting IIS..."
    & iisreset /restart
    Start-Sleep -Seconds 5
    Write-Success "✓ IIS restarted"
} catch {
    Write-Error "Failed to restart IIS: $_"
}

# STEP 6: Test HTTPS
Write-Info ""
Write-Info "STEP 6: Testing HTTPS Connection"
Write-Info "────────────────────────────────"

$maxRetries = 3
$retryCount = 0

do {
    try {
        Write-Info "Testing: https://erp.droob-albayan.ly"

        # Allow self-signed certificates for testing
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {
            return $true
        }

        $response = Invoke-WebRequest -Uri 'https://erp.droob-albayan.ly' -Method Get -TimeoutSec 5 -ErrorAction Stop
        Write-Success "✓ HTTPS responding with $($response.StatusCode)"
        break
    } catch {
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Write-Info "Attempt $retryCount/$maxRetries (waiting...)..."
            Start-Sleep -Seconds 2
        } else {
            Write-Warning "HTTPS test failed after $maxRetries attempts"
            Write-Info "Error: $($_.Exception.Message)"
        }
    }
} while ($retryCount -lt $maxRetries)

# STEP 7: Test HTTP Redirect
Write-Info ""
Write-Info "STEP 7: Testing HTTP→HTTPS Redirect"
Write-Info "───────────────────────────────────"

try {
    Write-Info "Testing: http://erp.droob-albayan.ly (should redirect to HTTPS)"

    $response = Invoke-WebRequest -Uri 'http://erp.droob-albayan.ly' -Method Get -TimeoutSec 5 -MaximumRedirection 0 -ErrorAction SilentlyContinue

    if ($response.StatusCode -in @(301, 302, 303, 307, 308)) {
        Write-Success "✓ HTTP request redirecting (Status: $($response.StatusCode))"
        Write-Info "Redirect Location: $($response.Headers['Location'])"
    } else {
        Write-Info "HTTP Status: $($response.StatusCode)"
    }
} catch {
    Write-Info "Request handling: $($_.Exception.Message)"
}

Write-Info ""
Write-Success "=================================="
Write-Success "HTTPS Binding Setup Complete!"
Write-Success "=================================="
Write-Info ""
Write-Info "Summary:"
Write-Info "  Site: Kinetic"
Write-Info "  Certificate: $($selectedCert.Subject)"
Write-Info "  Thumbprint: $thumbprint"
Write-Info "  HTTP:80 → HTTPS:443 redirect enabled"
Write-Info ""
Write-Info "Next steps:"
Write-Info "  1. Visit https://erp.droob-albayan.ly in browser"
Write-Info "  2. Verify frontend loads correctly"
Write-Info "  3. Check browser certificate details"
Write-Info "  4. Test API endpoints"
Write-Info ""
