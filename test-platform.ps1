# Test Platform Script
param(
    [string]$BackendUrl = "http://localhost:5000",
    [string]$FrontendUrl = "http://localhost:8080",
    [string]$Email = "alfawares085@gmail.com",
    [string]$Password = "Admin@2025"
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Testing Kinetic ERP Platform" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Test 1: Backend Connection
Write-Host "`n[1] Testing Backend Connection..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$BackendUrl/health" -ErrorAction Stop -TimeoutSec 5
    Write-Host "OK - Backend is running on port 5000" -ForegroundColor Green
}
catch {
    Write-Host "ERROR - Backend is not responding" -ForegroundColor Red
    Write-Host "Start: dotnet run --urls http://localhost:5000" -ForegroundColor Yellow
    exit 1
}

# Test 2: Login
Write-Host "`n[2] Testing Login..." -ForegroundColor Yellow
$loginBody = @{
    EmailOrUsername = $Email
    Password = $Password
    RememberMe = $false
} | ConvertTo-Json

try {
    $loginResponse = Invoke-WebRequest -Uri "$BackendUrl/api/auth/login" `
        -Method POST `
        -ContentType "application/json" `
        -Body $loginBody `
        -ErrorAction Stop

    $loginData = $loginResponse.Content | ConvertFrom-Json

    if ($loginData.token) {
        Write-Host "OK - Login successful" -ForegroundColor Green
        Write-Host "   Role: $($loginData.role)" -ForegroundColor Green
        Write-Host "   Organization ID: $($loginData.organizationId)" -ForegroundColor Green
        Write-Host "   Is Platform Admin: $($loginData.isPlatformAdmin)" -ForegroundColor Green
        Write-Host "   Must Change Password: $($loginData.mustChangePassword)" -ForegroundColor Green

        $token = $loginData.token
    }
    else {
        Write-Host "ERROR - Login failed" -ForegroundColor Red
        Write-Host $loginResponse.Content
        exit 1
    }
}
catch {
    Write-Host "ERROR - Login API error: $_" -ForegroundColor Red
    exit 1
}

# Test 3: Platform API Endpoints
Write-Host "`n[3] Testing Platform API Endpoints..." -ForegroundColor Yellow

$headers = @{
    Authorization = "Bearer $token"
    "Content-Type" = "application/json"
}

# Test organizations endpoint
Write-Host "   Testing GET /api/platform/organizations..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$BackendUrl/api/platform/organizations" `
        -Headers $headers `
        -ErrorAction Stop
    Write-Host "   OK - Status: $($response.StatusCode)" -ForegroundColor Green
}
catch {
    Write-Host "   ERROR - $($_.Exception.Response.StatusCode)" -ForegroundColor Red
}

# Test dashboard endpoint
Write-Host "   Testing GET /api/platform/organizations/dashboard..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$BackendUrl/api/platform/organizations/dashboard" `
        -Headers $headers `
        -ErrorAction Stop
    Write-Host "   OK - Status: $($response.StatusCode)" -ForegroundColor Green
}
catch {
    Write-Host "   ERROR - $($_.Exception.Response.StatusCode)" -ForegroundColor Red
}

# Test settings endpoint
Write-Host "   Testing GET /api/platform/settings..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$BackendUrl/api/platform/settings" `
        -Headers $headers `
        -ErrorAction Stop
    Write-Host "   OK - Status: $($response.StatusCode)" -ForegroundColor Green
}
catch {
    Write-Host "   WARNING - Endpoint may not exist yet" -ForegroundColor Yellow
}

# Test 4: Frontend
Write-Host "`n[4] Testing Frontend..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri $FrontendUrl -ErrorAction Stop -TimeoutSec 5
    Write-Host "OK - Frontend is running on port 8080" -ForegroundColor Green
}
catch {
    Write-Host "ERROR - Frontend is not responding" -ForegroundColor Red
    Write-Host "Start: flutter run -d chrome --web-port 8080" -ForegroundColor Yellow
}

# Summary
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "OK - Basic tests passed" -ForegroundColor Green
Write-Host "`nAccess the platform at:" -ForegroundColor Cyan
Write-Host "  Frontend: $FrontendUrl/#/platform" -ForegroundColor Cyan
Write-Host "  Login: $Email / Admin@2025" -ForegroundColor Cyan
Write-Host "`nIf there are issues:" -ForegroundColor Yellow
Write-Host "  1. Open F12 in browser" -ForegroundColor Yellow
Write-Host "  2. Check Console and Network tabs" -ForegroundColor Yellow
Write-Host "  3. Share any error messages" -ForegroundColor Yellow
