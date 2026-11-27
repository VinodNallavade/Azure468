$ErrorActionPreference = "Stop"
$tenantId = "917452516ce24"
$tags = @{Environment="Production"; Owner="Vinod"}
Connect-AzAccount -TenantId $tenantId

# ================================================
# 1. Variables
# ================================================

$location = "centralindia"
$suffix = Get-Random -Minimum 10000 -Maximum 99999

$rgName       = "rg-waf-demo-$suffix"
$vnetName     = "vnet-waf-demo"
$subnetName   = "snet-appgateway"
$pipName      = "pip-appgateway"
$appGwName    = "agw-waf-demo"
$planName     = "asp-waf-demo"
$webAppName   = "app-waf-demo-$suffix"
$wafName      = "policy-waf-demo"
$workspaceName = "law-waf-demo-$suffix"

# ================================================
# 2. Create Resource Group
# ================================================

Write-Host "Creating Resource Group..." -ForegroundColor Cyan

New-AzResourceGroup `
    -Name $rgName `
    -Location $location | Out-Null

# ================================================
# 3. Create Virtual Network and Subnet
# ================================================

Write-Host "Creating Virtual Network..." -ForegroundColor Cyan

$subnet = New-AzVirtualNetworkSubnetConfig `
    -Name $subnetName `
    -AddressPrefix "10.0.1.0/24"

$vnet = New-AzVirtualNetwork `
    -Name $vnetName `
    -ResourceGroupName $rgName `
    -Location $location `
    -AddressPrefix "10.0.0.0/16" `
    -Subnet $subnet

$subnet = Get-AzVirtualNetworkSubnetConfig `
    -Name $subnetName `
    -VirtualNetwork $vnet

# ================================================
# 4. Create Public IP
# ================================================

Write-Host "Creating Public IP..." -ForegroundColor Cyan

$pip = New-AzPublicIpAddress `
    -Name $pipName `
    -ResourceGroupName $rgName `
    -Location $location `
    -AllocationMethod Static `
    -Sku Standard

# ================================================
# 5. Create App Service Plan and Web App
# ================================================

Write-Host "Creating Azure Web App..." -ForegroundColor Cyan

New-AzAppServicePlan `
    -Name $planName `
    -ResourceGroupName $rgName `
    -Location $location `
    -Tier Basic `
    -WorkerSize Small | Out-Null

$webApp = New-AzWebApp `
    -Name $webAppName `
    -ResourceGroupName $rgName `
    -Location $location `
    -AppServicePlan $planName

$backendHost = $webApp.DefaultHostName

Write-Host "Web App: https://$backendHost" `
    -ForegroundColor Green

# ================================================
# 6. Create WAF Policy in Detection Mode
# ================================================
# ================================================
# 6. Create WAF Policy in Detection Mode
# ================================================

Write-Host "Creating WAF Policy..." -ForegroundColor Cyan

$policySettings = New-AzApplicationGatewayFirewallPolicySetting `
    -State Enabled `
    -Mode Detection

$managedRuleSet = New-AzApplicationGatewayFirewallPolicyManagedRuleSet `
    -RuleSetType "OWASP" `
    -RuleSetVersion "3.2"

$managedRules = New-AzApplicationGatewayFirewallPolicyManagedRule `
    -ManagedRuleSet $managedRuleSet

$wafPolicy = New-AzApplicationGatewayFirewallPolicy `
    -Name $wafName `
    -ResourceGroupName $rgName `
    -Location $location `
    -PolicySetting $policySettings `
    -ManagedRule $managedRules

$wafPolicy.PolicySettings | Format-List
# ================================================
# 7. Configure Application Gateway
# ================================================

Write-Host "Configuring Application Gateway..." -ForegroundColor Cyan

$gatewayIP = New-AzApplicationGatewayIPConfiguration `
    -Name "gateway-ip-config" `
    -Subnet $subnet

$frontendIP = New-AzApplicationGatewayFrontendIPConfig `
    -Name "frontend-ip" `
    -PublicIPAddress $pip

$frontendPort = New-AzApplicationGatewayFrontendPort `
    -Name "http-port" `
    -Port 80

# Backend Pool

$backendPool = New-AzApplicationGatewayBackendAddressPool `
    -Name "backend-pool" `
    -BackendFqdns $backendHost

# Health Probe

$probe = New-AzApplicationGatewayProbeConfig `
    -Name "webapp-probe" `
    -Protocol Https `
    -HostName $backendHost `
    -Path "/" `
    -Interval 30 `
    -Timeout 30 `
    -UnhealthyThreshold 3

# Backend HTTP Settings

$backendSettings = New-AzApplicationGatewayBackendHttpSetting `
    -Name "backend-https-settings" `
    -Port 443 `
    -Protocol Https `
    -CookieBasedAffinity Disabled `
    -RequestTimeout 30 `
    -PickHostNameFromBackendAddress `
    -Probe $probe

# HTTP Listener

$listener = New-AzApplicationGatewayHttpListener `
    -Name "http-listener" `
    -Protocol Http `
    -FrontendIPConfiguration $frontendIP `
    -FrontendPort $frontendPort

# Routing Rule

$rule = New-AzApplicationGatewayRequestRoutingRule `
    -Name "default-routing-rule" `
    -RuleType Basic `
    -Priority 100 `
    -HttpListener $listener `
    -BackendAddressPool $backendPool `
    -BackendHttpSettings $backendSettings

# SKU

$sku = New-AzApplicationGatewaySku `
    -Name WAF_v2 `
    -Tier WAF_v2 `
    -Capacity 1

# ================================================
# 8. Deploy Application Gateway
# ================================================

Write-Host "Deploying Application Gateway..." -ForegroundColor Cyan

$appGw = New-AzApplicationGateway `
    -Name $appGwName `
    -ResourceGroupName $rgName `
    -Location $location `
    -Sku $sku `
    -GatewayIpConfigurations $gatewayIP `
    -FrontendIpConfigurations $frontendIP `
    -FrontendPorts $frontendPort `
    -BackendAddressPools $backendPool `
    -BackendHttpSettingsCollection $backendSettings `
    -HttpListeners $listener `
    -RequestRoutingRules $rule `
    -Probes $probe `
    -FirewallPolicy $wafPolicy

# ================================================
# 9. Create Log Analytics Workspace
# ================================================

Write-Host "Creating Log Analytics Workspace..." `
    -ForegroundColor Cyan

$workspace = New-AzOperationalInsightsWorkspace `
    -Name $workspaceName `
    -ResourceGroupName $rgName `
    -Location $location `
    -Sku PerGB2018

$firewallLog = New-AzDiagnosticSettingLogSettingsObject `
    -Enabled $true `
    -Category "ApplicationGatewayFirewallLog"

$accessLog = New-AzDiagnosticSettingLogSettingsObject `
    -Enabled $true `
    -Category "ApplicationGatewayAccessLog"

New-AzDiagnosticSetting `
    -Name "waf-diagnostics" `
    -ResourceId $appGw.Id `
    -WorkspaceId $workspace.ResourceId `
    -LogAnalyticsDestinationType Dedicated `
    -Log @($firewallLog, $accessLog) | Out-Null

# ================================================
# 10. Get Application Gateway URL
# ================================================

$pip = Get-AzPublicIpAddress `
    -Name $pipName `
    -ResourceGroupName $rgName

$baseUrl = "http://$($pip.IpAddress)"

Write-Host "`n========================================"
Write-Host "DEPLOYMENT COMPLETED"
Write-Host "========================================"
Write-Host "Resource Group : $rgName"
Write-Host "Gateway URL    : $baseUrl"
Write-Host "Backend URL    : https://$backendHost"
Write-Host "WAF Mode       : Detection"
Write-Host "========================================"

# ================================================
# 11. Check Backend Health
# ================================================

Get-AzApplicationGatewayBackendHealth `
    -Name $appGwName `
    -ResourceGroupName $rgName |
    ConvertTo-Json -Depth 10

# ================================================
# 12. HTTP Request Testing Function
# ================================================

function Test-WebRequest {

    param (
        [string]$TestName,
        [string]$Url
    )

    try {
        $response = Invoke-WebRequest `
    -Uri "$baseUrl/" `
    -Headers @{
        "Accept" = "text/html,application/xhtml+xml,*/*"
    } `
    -UseBasicParsing

        Write-Host "$TestName : HTTP $($response.StatusCode)" `
            -ForegroundColor Green
    }
    catch {

        if ($null -ne $_.Exception.Response) {

            $status = [int]$_.Exception.Response.StatusCode

            Write-Host "$TestName : HTTP $status" `
                -ForegroundColor Yellow
        }
        else {
            Write-Host "$TestName : $($_.Exception.Message)" `
                -ForegroundColor Red
        }
    }
}

# Sample security test strings
# Use only against your own lab application.

$sqlTest = [uri]::EscapeDataString("' OR 1=1 --")
$xssTest = [uri]::EscapeDataString("<script>alert(1)</script>")

# ================================================
# 13. Test Detection Mode
# ================================================

Read-Host "Verify backend health, then press Enter to test Detection mode"

Write-Host "`n===== DETECTION MODE =====" `
    -ForegroundColor Cyan

Test-WebRequest "Normal Request" `
    "$baseUrl/"

Test-WebRequest "SQL Injection Test" `
    "$baseUrl/?id=$sqlTest"

Test-WebRequest "XSS Test" `
    "$baseUrl/?search=$xssTest"

# ================================================
# 14. Switch WAF to Prevention Mode
# ================================================

Read-Host "Press Enter to enable Prevention mode"

$wafPolicy = Get-AzApplicationGatewayFirewallPolicy `
    -Name $wafName `
    -ResourceGroupName $rgName

$wafPolicy.PolicySettings.Mode = "Prevention"

$wafPolicy = Set-AzApplicationGatewayFirewallPolicy `
    -InputObject $wafPolicy

Write-Host "WAF Prevention Mode enabled." `
    -ForegroundColor Green

# ================================================
# 15. Test Prevention Mode
# ================================================

Read-Host "Wait for the policy update to propagate, then press Enter"

Write-Host "`n===== PREVENTION MODE =====" `
    -ForegroundColor Cyan

Test-WebRequest "Normal Request" `
    "$baseUrl/"

Test-WebRequest "SQL Injection Test" `
    "$baseUrl/?id=$sqlTest"

Test-WebRequest "XSS Test" `
    "$baseUrl/?search=$xssTest"

# ================================================
# 16. Create Custom WAF Rule
# ================================================

Read-Host "Press Enter to create a Custom WAF Rule"

# Block requests containing 'blockme'
# in the query string.

$matchVariable = New-AzApplicationGatewayFirewallMatchVariable `
    -VariableName "QueryString"

$matchCondition = New-AzApplicationGatewayFirewallCondition `
    -MatchVariable $matchVariable `
    -Operator Contains `
    -MatchValue "blockme"

$customRule = New-AzApplicationGatewayFirewallCustomRule `
    -Name "BlockCustomQueryString" `
    -Priority 9 `
    -RuleType MatchRule `
    -MatchCondition $matchCondition `
    -Action Block

$wafPolicy = Get-AzApplicationGatewayFirewallPolicy `
    -Name $wafName `
    -ResourceGroupName $rgName

$wafPolicy.CustomRules.Add($customRule)

$wafPolicy = Set-AzApplicationGatewayFirewallPolicy `
    -InputObject $wafPolicy

# ================================================
# 17. Test Custom Rule
# ================================================

Read-Host "Wait for the custom rule to propagate, then press Enter"

Write-Host "`n===== CUSTOM RULE TEST =====" `
    -ForegroundColor Cyan

Test-WebRequest "Allowed Request" `
    "$baseUrl/?message=hello"

Test-WebRequest "Blocked Request" `
    "$baseUrl/?message=blockme"

# ================================================
# 18. Display WAF Configuration
# ================================================

$wafPolicy = Get-AzApplicationGatewayFirewallPolicy `
    -Name $wafName `
    -ResourceGroupName $rgName

$wafPolicy.PolicySettings | Format-List

$wafPolicy.CustomRules |
    Select-Object Name, Priority, RuleType, Action |
    Format-Table

# ================================================
# 19. Query Firewall Logs
# ================================================

Read-Host "Press Enter to query WAF logs"

$query = @"
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| project TimeGenerated, ClientIp,
          RequestUri, RuleId, Action, Message
| order by TimeGenerated desc
| take 30
"@

try {
    $results = Invoke-AzOperationalInsightsQuery `
        -WorkspaceId $workspace.CustomerId `
        -Query $query

    $results.Results | Format-Table -AutoSize
}
catch {
    Write-Warning "Logs may not be available yet. Retry later."
}

# ================================================
# 20. Cleanup
# ================================================

Write-Host "`nLab completed." -ForegroundColor Green
Write-Host "Resource Group: $rgName"
Write-Host "Gateway URL: $baseUrl"

$cleanup = Read-Host "Delete all lab resources? (yes/no)"

if ($cleanup -eq "yes") {

    Remove-AzResourceGroup `
        -Name $rgName `
        -Force

    Write-Host "Lab resources deleted." `
        -ForegroundColor Green
}
else {
    Write-Warning "Resources retained. Azure charges continue."
}



