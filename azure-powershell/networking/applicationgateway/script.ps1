# ============================================================
# AZURE APPLICATION GATEWAY WITH WEB APP BACKENDS
# ============================================================

$ErrorActionPreference = 'Stop'
$tenantId          = "91f820e7-a557-448d-8ccf-c7452516ce24"
$tags              = @{Environment="Production"; Owner="Vinod"}

# ============================================================
# STEP 1: CONNECT TO AZURE
# ============================================================

if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
      Connect-AzAccount -TenantId $tenantId 
}

# Set-AzContext -SubscriptionId "<Subscription-ID>"

# ============================================================
# STEP 2: VARIABLES
# ============================================================

$location = "centralindia"
$suffix = ([guid]::NewGuid().ToString("N")).Substring(0,8)

$rgName   = "RG-AppGW-WebApp-Lab"
$vnetName = "VNet-AppGW"
$planName = "ASP-AppGW-Lab"

$app1Name = "appgw-app1-$suffix"
$app2Name = "appgw-app2-$suffix"

$appGwName = "AppGW-Demo"
$pipName   = "PIP-AppGW"

if (Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue) {
    throw "Resource group already exists. Use a different name."
}

# ============================================================
# STEP 3: CREATE RESOURCE GROUP
# ============================================================

Write-Host "`nCreating Resource Group..." -ForegroundColor Cyan

New-AzResourceGroup `
    -Name $rgName `
    -Location $location | Out-Null

# ============================================================
# STEP 4: CREATE APP SERVICE PLAN
# ============================================================

Write-Host "`nCreating App Service Plan..." -ForegroundColor Cyan

$plan = New-AzAppServicePlan `
    -ResourceGroupName $rgName `
    -Name $planName `
    -Location $location `
    -Tier Basic `
    -WorkerSize Small `
    -NumberofWorkers 1

# ============================================================
# STEP 5: CREATE TWO WEB APPS
# ============================================================

Write-Host "`nCreating Web Apps..." -ForegroundColor Cyan

$app1 = New-AzWebApp `
    -ResourceGroupName $rgName `
    -Name $app1Name `
    -Location $location `
    -AppServicePlan $planName

$app2 = New-AzWebApp `
    -ResourceGroupName $rgName `
    -Name $app2Name `
    -Location $location `
    -AppServicePlan $planName

# Enable HTTPS Only

Set-AzWebApp `
    -ResourceGroupName $rgName `
    -Name $app1Name `
    -HttpsOnly $true | Out-Null

Set-AzWebApp `
    -ResourceGroupName $rgName `
    -Name $app2Name `
    -HttpsOnly $true | Out-Null

# Retrieve actual Web App hostnames

$app1Host = $app1.DefaultHostName
$app2Host = $app2.DefaultHostName

Write-Host "Web App 1: https://$app1Host"
Write-Host "Web App 2: https://$app2Host"

# ============================================================
# STEP 6: CREATE AND DEPLOY SAMPLE WEBSITES
# ============================================================

$tempFolder = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    "AppGW-Lab-$suffix"

New-Item `
    -Path $tempFolder `
    -ItemType Directory `
    -Force | Out-Null

$webApps = @(
    @{
        Name  = $app1Name
        Title = "Application 1"
        Path  = "app1"
        Color = "#0078D4"
        HostName = $app1Host
    },
    @{
        Name  = $app2Name
        Title = "Application 2"
        Path  = "app2"
        Color = "#107C10"
        HostName = $app2Host
    }
)

foreach ($webApp in $webApps) {

    Write-Host "`nDeploying $($webApp.Title)..." `
        -ForegroundColor Cyan

    $contentFolder = Join-Path `
        $tempFolder $webApp.Path

    New-Item `
        -Path $contentFolder `
        -ItemType Directory `
        -Force | Out-Null

    $applicationFolder = Join-Path `
        $contentFolder $webApp.Path

    New-Item `
        -Path $applicationFolder `
        -ItemType Directory `
        -Force | Out-Null

    # Sample HTML page

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>$($webApp.Title)</title>
</head>
<body style="font-family:Arial;text-align:center;padding:60px;">
    <h1 style="color:$($webApp.Color);">
        $($webApp.Title)
    </h1>
    <h2>Azure Application Gateway Lab</h2>
    <p>Hosted on Azure App Service</p>
    <p>Backend: $($webApp.Name)</p>
    <p>Hostname: $($webApp.HostName)</p>
</body>
</html>
"@

    # Create root homepage

    $html | Set-Content `
        (Join-Path $contentFolder "index.html")

    # Create application-specific path

    $html | Set-Content `
        (Join-Path $applicationFolder "index.html")

    # Create health endpoint

    "Healthy - $($webApp.Name)" |
        Set-Content `
        (Join-Path $contentFolder "health.html")

    # Create ZIP deployment package

    $zipPath = Join-Path `
        $tempFolder "$($webApp.Path).zip"

    Compress-Archive `
        -Path "$contentFolder/*" `
        -DestinationPath $zipPath `
        -Force

    # Deploy ZIP to Web App

    Publish-AzWebApp `
        -ResourceGroupName $rgName `
        -Name $webApp.Name `
        -ArchivePath $zipPath `
        -Force | Out-Null
}

# ============================================================
# STEP 7: TEST WEB APPS DIRECTLY
# ============================================================

function Wait-WebApp {

    param([string]$HostName)

    for ($attempt = 1; $attempt -le 30; $attempt++) {

        try {

            $response = Invoke-WebRequest `
                -Uri "https://$HostName/health.html" `
                -UseBasicParsing `
                -TimeoutSec 15

            if ($response.StatusCode -eq 200 -and
                $response.Content -match "Healthy") {

                Write-Host "$HostName is ready" `
                    -ForegroundColor Green

                return
            }

        }
        catch {
            Write-Host "Waiting for $HostName..."
        }

        Start-Sleep -Seconds 10
    }

    throw "Web App did not become ready: $HostName"
}

Wait-WebApp -HostName $app1Host
Wait-WebApp -HostName $app2Host

Write-Host "`nDirect Web App URLs:" -ForegroundColor Green

Write-Host "https://$app1Host/"
Write-Host "https://$app2Host/"

Read-Host "`nPress Enter to create Application Gateway"

# ============================================================
# STEP 8: CREATE VIRTUAL NETWORK
# ============================================================

Write-Host "`nCreating Virtual Network..." `
    -ForegroundColor Cyan

$subnetConfig = New-AzVirtualNetworkSubnetConfig `
    -Name "AppGatewaySubnet" `
    -AddressPrefix "10.0.1.0/24"

$vnet = New-AzVirtualNetwork `
    -ResourceGroupName $rgName `
    -Name $vnetName `
    -Location $location `
    -AddressPrefix "10.0.0.0/16" `
    -Subnet $subnetConfig

$subnet = Get-AzVirtualNetworkSubnetConfig `
    -Name "AppGatewaySubnet" `
    -VirtualNetwork $vnet

# ============================================================
# STEP 9: CREATE PUBLIC IP
# ============================================================

$pip = New-AzPublicIpAddress `
    -ResourceGroupName $rgName `
    -Name $pipName `
    -Location $location `
    -AllocationMethod Static `
    -Sku Standard

# ============================================================
# STEP 10: APPLICATION GATEWAY CONFIGURATION
# ============================================================

# Gateway IP Configuration

$gatewayIP = New-AzApplicationGatewayIPConfiguration `
    -Name "GatewayIPConfig" `
    -Subnet $subnet

# Frontend IP Configuration

$frontendIP = New-AzApplicationGatewayFrontendIPConfig `
    -Name "FrontendIPConfig" `
    -PublicIPAddress $pip

# Frontend Port

$frontendPort = New-AzApplicationGatewayFrontendPort `
    -Name "FrontendPort80" `
    -Port 80

# ============================================================
# STEP 11: CREATE BACKEND POOLS
# ============================================================

# Default Pool - Both Web Apps

$defaultPool = New-AzApplicationGatewayBackendAddressPool `
    -Name "DefaultBackendPool" `
    -BackendFqdns $app1Host, $app2Host

# Application 1 Pool

$app1Pool = New-AzApplicationGatewayBackendAddressPool `
    -Name "App1BackendPool" `
    -BackendFqdns $app1Host

# Application 2 Pool

$app2Pool = New-AzApplicationGatewayBackendAddressPool `
    -Name "App2BackendPool" `
    -BackendFqdns $app2Host

# ============================================================
# STEP 12: CREATE CUSTOM HEALTH PROBE
# ============================================================

$probe = New-AzApplicationGatewayProbeConfig `
    -Name "WebAppHealthProbe" `
    -Protocol Https `
    -PickHostNameFromBackendHttpSettings `
    -Path "/health.html" `
    -Interval 15 `
    -Timeout 10 `
    -UnhealthyThreshold 3

# ============================================================
# STEP 13: CREATE BACKEND HTTP SETTINGS
# ============================================================

$httpSettings = New-AzApplicationGatewayBackendHttpSetting `
    -Name "WebAppHTTPSSettings" `
    -Protocol Https `
    -Port 443 `
    -PickHostNameFromBackendAddress `
    -CookieBasedAffinity Disabled `
    -RequestTimeout 30 `
    -Probe $probe

# IMPORTANT:
# PickHostNameFromBackendAddress ensures that the correct
# Azure Web App hostname is sent to the backend.

# ============================================================
# STEP 14: CREATE HTTP LISTENER
# ============================================================

$listener = New-AzApplicationGatewayHttpListener `
    -Name "HTTPListener" `
    -Protocol Http `
    -FrontendIPConfiguration $frontendIP `
    -FrontendPort $frontendPort

# ============================================================
# STEP 15: CREATE URL PATH RULES
# ============================================================

$app1Rule = New-AzApplicationGatewayPathRuleConfig `
    -Name "App1PathRule" `
    -Paths "/app1", "/app1/*" `
    -BackendAddressPool $app1Pool `
    -BackendHttpSettings $httpSettings

$app2Rule = New-AzApplicationGatewayPathRuleConfig `
    -Name "App2PathRule" `
    -Paths "/app2", "/app2/*" `
    -BackendAddressPool $app2Pool `
    -BackendHttpSettings $httpSettings

# Create URL Path Map

$urlPathMap = New-AzApplicationGatewayUrlPathMapConfig `
    -Name "WebAppPathMap" `
    -PathRules $app1Rule, $app2Rule `
    -DefaultBackendAddressPool $defaultPool `
    -DefaultBackendHttpSettings $httpSettings

# Create Routing Rule

$routingRule = New-AzApplicationGatewayRequestRoutingRule `
    -Name "PathBasedRoutingRule" `
    -RuleType PathBasedRouting `
    -Priority 100 `
    -HttpListener $listener `
    -UrlPathMap $urlPathMap

# ============================================================
# STEP 16: CONFIGURE SKU
# ============================================================

$sku = New-AzApplicationGatewaySku `
    -Name Standard_v2 `
    -Tier Standard_v2 `
    -Capacity 1

# ============================================================
# STEP 17: DEPLOY APPLICATION GATEWAY
# ============================================================

Write-Host "`nDeploying Application Gateway..." `
    -ForegroundColor Yellow

$appGw = New-AzApplicationGateway `
    -ResourceGroupName $rgName `
    -Name $appGwName `
    -Location $location `
    -Sku $sku `
    -GatewayIPConfigurations $gatewayIP `
    -FrontendIPConfigurations $frontendIP `
    -FrontendPorts $frontendPort `
    -BackendAddressPools $defaultPool, $app1Pool, $app2Pool `
    -BackendHttpSettingsCollection $httpSettings `
    -HttpListeners $listener `
    -RequestRoutingRules $routingRule `
    -UrlPathMaps $urlPathMap `
    -Probes $probe

$publicIP = (Get-AzPublicIpAddress `
    -ResourceGroupName $rgName `
    -Name $pipName).IpAddress

$baseUrl = "http://$publicIP"

Write-Host "`nApplication Gateway deployed!" `
    -ForegroundColor Green

Write-Host "Gateway URL: $baseUrl"

# ============================================================
# HELPER FUNCTION: GET BACKEND HEALTH
# ============================================================

function Get-BackendHealth {

    $health = Get-AzApplicationGatewayBackendHealth `
        -ResourceGroupName $rgName `
        -Name $appGwName

    foreach ($pool in $health.BackendAddressPools) {

        $poolName = ($pool.BackendAddressPool.Id -split "/")[-1]

        foreach ($setting in $pool.BackendHttpSettingsCollection) {

            foreach ($server in $setting.Servers) {

                [PSCustomObject]@{
                    Pool    = $poolName
                    Backend = $server.Address
                    Health  = $server.Health
                    Details = $server.HealthProbeLog
                }
            }
        }
    }
}

function Show-BackendHealth {

    Write-Host "`nBackend Health:" -ForegroundColor Cyan

    Get-BackendHealth | Format-Table -AutoSize
}

function Wait-BackendHealth {

    param(
        [string]$PoolName,
        [string]$ExpectedHealth
    )

    for ($attempt = 1; $attempt -le 30; $attempt++) {

        $servers = @(Get-BackendHealth | Where-Object {
            $_.Pool -eq $PoolName
        })

        $unexpected = @($servers | Where-Object {
            $_.Health -ne $ExpectedHealth
        })

        if ($servers.Count -gt 0 -and
            $unexpected.Count -eq 0) {

            Write-Host "$PoolName : $ExpectedHealth" `
                -ForegroundColor Green

            return
        }

        Write-Host "Waiting for $PoolName to become $ExpectedHealth..."

        Start-Sleep -Seconds 15
    }

    Show-BackendHealth

    throw "Backend health check timed out for $PoolName"
}

# ============================================================
# HELPER FUNCTION: TEST APPLICATION GATEWAY
# ============================================================

function Test-AppGateway {

    param(
        [string]$Path = "/",
        [int]$Count = 5,
        [switch]$KeepCookies
    )

    Write-Host "`nTesting $baseUrl$Path" `
        -ForegroundColor Cyan

    $session = New-Object `
        Microsoft.PowerShell.Commands.WebRequestSession

    for ($i = 1; $i -le $Count; $i++) {

        try {

            if (-not $KeepCookies) {
                $session = New-Object `
                    Microsoft.PowerShell.Commands.WebRequestSession
            }

            $response = Invoke-WebRequest `
                -Uri "$baseUrl$Path" `
                -UseBasicParsing `
                -DisableKeepAlive `
                -WebSession $session `
                -TimeoutSec 30

            $backend = [regex]::Match(
                $response.Content,
                "appgw-app[12]-[a-f0-9]{8}"
            ).Value

            Write-Host `
                "Request $i : HTTP $($response.StatusCode) - $backend" `
                -ForegroundColor Green

        }
        catch {

            $statusCode = "Connection Error"

            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            Write-Host "Request $i : HTTP $statusCode" `
                -ForegroundColor Red
        }
    }

    if ($KeepCookies) {

        $session.Cookies.GetCookies(
            [uri]"$baseUrl$Path"
        ) | Format-Table Name, Value
    }
}

# ============================================================
# DEMO 1: CHECK BACKEND HEALTH
# ============================================================

Wait-BackendHealth `
    -PoolName "DefaultBackendPool" `
    -ExpectedHealth "Healthy"

Wait-BackendHealth `
    -PoolName "App1BackendPool" `
    -ExpectedHealth "Healthy"

Wait-BackendHealth `
    -PoolName "App2BackendPool" `
    -ExpectedHealth "Healthy"

Show-BackendHealth

# ============================================================
# DEMO 2: LOAD BALANCING
# ============================================================

Write-Host "`nDEMO: LOAD BALANCING" -ForegroundColor Yellow

Test-AppGateway -Path "/" -Count 10

Read-Host "`nPress Enter to test Path-Based Routing"

# ============================================================
# DEMO 3: PATH-BASED ROUTING
# ============================================================

Write-Host "`nDEMO: PATH-BASED ROUTING" `
    -ForegroundColor Yellow

Test-AppGateway -Path "/app1/" -Count 3

Test-AppGateway -Path "/app2/" -Count 3

Write-Host "`nOpen the following URLs in browser:"

Write-Host "$baseUrl/"
Write-Host "$baseUrl/app1/"
Write-Host "$baseUrl/app2/"

Read-Host "`nPress Enter to simulate Web App failure"

# ============================================================
# DEMO 4: BACKEND FAILURE
# ============================================================

Write-Host "`nStopping Application 1..." `
    -ForegroundColor Yellow

try {

    Stop-AzWebApp `
        -ResourceGroupName $rgName `
        -Name $app1Name | Out-Null

    Wait-BackendHealth `
        -PoolName "App1BackendPool" `
        -ExpectedHealth "Unhealthy"

    Show-BackendHealth

    # Default pool should use healthy Application 2

    Test-AppGateway -Path "/" -Count 5

    # Application 1 should return 502

    Test-AppGateway -Path "/app1/" -Count 2

    # Application 2 should continue working

    Test-AppGateway -Path "/app2/" -Count 3

    Read-Host "`nPress Enter to restart Application 1"

}
finally {

    Start-AzWebApp `
        -ResourceGroupName $rgName `
        -Name $app1Name | Out-Null
}

# ============================================================
# DEMO 5: BACKEND RECOVERY
# ============================================================

Write-Host "`nDEMO: BACKEND RECOVERY" `
    -ForegroundColor Yellow

Wait-BackendHealth `
    -PoolName "DefaultBackendPool" `
    -ExpectedHealth "Healthy"

Wait-BackendHealth `
    -PoolName "App1BackendPool" `
    -ExpectedHealth "Healthy"

Show-BackendHealth

Test-AppGateway -Path "/" -Count 6

Test-AppGateway -Path "/app1/" -Count 3

Read-Host "`nPress Enter to enable Session Affinity"

# ============================================================
# DEMO 6: COOKIE-BASED SESSION AFFINITY
# ============================================================

$appGw = Get-AzApplicationGateway `
    -ResourceGroupName $rgName `
    -Name $appGwName

$probe = Get-AzApplicationGatewayProbeConfig `
    -ApplicationGateway $appGw `
    -Name "WebAppHealthProbe"

$appGw = Set-AzApplicationGatewayBackendHttpSetting `
    -ApplicationGateway $appGw `
    -Name "WebAppHTTPSSettings" `
    -Protocol Https `
    -Port 443 `
    -PickHostNameFromBackendAddress `
    -CookieBasedAffinity Enabled `
    -RequestTimeout 30 `
    -Probe $probe

$appGw = Set-AzApplicationGateway `
    -ApplicationGateway $appGw

Wait-BackendHealth `
    -PoolName "DefaultBackendPool" `
    -ExpectedHealth "Healthy"

Test-AppGateway `
    -Path "/" `
    -Count 10 `
    -KeepCookies

# ============================================================
# FINAL SUMMARY
# ============================================================

Write-Host "`n========================================"
Write-Host "APPLICATION GATEWAY LAB COMPLETED"
Write-Host "========================================"

Write-Host "Resource Group : $rgName"
Write-Host "Web App 1      : https://$app1Host"
Write-Host "Web App 2      : https://$app2Host"

Write-Host "`nApplication Gateway URLs:"

Write-Host "Default : $baseUrl/"
Write-Host "App1    : $baseUrl/app1/"
Write-Host "App2    : $baseUrl/app2/"

Show-BackendHealth

# Remove local deployment files

Remove-Item `
    -Path $tempFolder `
    -Recurse `
    -Force

# ============================================================
# CLEANUP
# ============================================================

$cleanup = Read-Host "`nDelete all Azure resources? (Y/N)"

if ($cleanup -eq "Y") {

    Remove-AzResourceGroup `
        -Name $rgName `
        -Force

    Write-Host "Lab resources deleted" `
        -ForegroundColor Green

}
else {

    Write-Host "Resources retained. Charges continue." `
        -ForegroundColor Yellow

    Write-Host "Cleanup command:"
    Write-Host "Remove-AzResourceGroup -Name '$rgName' -Force"
}