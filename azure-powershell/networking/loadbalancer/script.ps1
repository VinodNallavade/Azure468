# Azure Public Standard Load Balancer - End-to-End Classroom Lab
# Prerequisites: Az PowerShell modules, Azure subscription, permission to create resources
# Runs in Azure Cloud Shell (PowerShell) or local PowerShell with Az modules.
# Creates billable resources. Use cleanup command at the end when finished.
$ErrorActionPreference = 'Stop'
$tenantId          = "91f820e7-a557-448d-8ccf-c7452516ce24"
$tags              = @{Environment="Production"; Owner="Vinod"}
$rg = 'rg-lb-class-demo'
$location = 'centralindia'
$vnetName = 'vnet-lb-class'
$subnetName = 'snet-web'
$lbName = 'lb-web-class'
$vmNames = @('vm-web-01','vm-web-02')
$vmSize = 'Standard_B2s' # Change if unavailable for your subscription/region.

# 0. Login / select subscription
if (-not (Get-AzContext -ErrorAction SilentlyContinue)) { Connect-AzAccount -TenantId $tenantId }
# Set-AzContext -SubscriptionId '<your-subscription-id>'
Write-Host "Using subscription: $((Get-AzContext).Subscription.Name)" -ForegroundColor Cyan
# DEMO ONLY: hardcoded credentials are insecure. Never use in production.
# Change the password before running and delete the resource group after class.
$adminUsername = 'azurelabadmin'
$adminPassword = 'LabDemo!2026#Vm42'
$securePassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
$credential = [System.Management.Automation.PSCredential]::new($adminUsername, $securePassword)

# 1. Resource Group
New-AzResourceGroup -Name $rg -Location $location | Out-Null

# 2. VNet and Subnet
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix '10.10.1.0/24'
$vnet = New-AzVirtualNetwork -ResourceGroupName $rg -Location $location `
    -Name $vnetName -AddressPrefix '10.10.0.0/16' -Subnet $subnetConfig
$subnet = $vnet.Subnets | Where-Object Name -EQ $subnetName

# 3. NSG: allow HTTP and load balancer probes (no public RDP)
$httpRule = New-AzNetworkSecurityRuleConfig -Name 'allow-http' -Priority 100 `
    -Direction Inbound -Access Allow -Protocol Tcp -SourceAddressPrefix Internet `
    -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange 80
$probeRule = New-AzNetworkSecurityRuleConfig -Name 'allow-lb-probe' -Priority 110 `
    -Direction Inbound -Access Allow -Protocol Tcp -SourceAddressPrefix AzureLoadBalancer `
    -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange 80
$nsg = New-AzNetworkSecurityGroup -Name 'nsg-lb-web' -ResourceGroupName $rg `
    -Location $location -SecurityRules $httpRule,$probeRule

# 4. Standard Public IP
$pip = New-AzPublicIpAddress -Name 'pip-lb-web' -ResourceGroupName $rg `
    -Location $location -Sku Standard -AllocationMethod Static

# 5. Load Balancer components
$frontend = New-AzLoadBalancerFrontendIpConfig -Name 'fe-public' -PublicIpAddress $pip
$backend = New-AzLoadBalancerBackendAddressPoolConfig -Name 'pool-web'
$probe = New-AzLoadBalancerProbeConfig -Name 'probe-tcp-80' -Protocol Tcp `
    -Port 80 -IntervalInSeconds 5 -ProbeCount 2
$rule = New-AzLoadBalancerRuleConfig -Name 'rule-http-80' -Protocol Tcp `
    -FrontendPort 80 -BackendPort 80 -FrontendIpConfiguration $frontend `
    -BackendAddressPool $backend -Probe $probe -DisableOutboundSNAT
$lb = New-AzLoadBalancer -Name $lbName -ResourceGroupName $rg -Location $location `
    -Sku Standard -FrontendIpConfiguration $frontend -BackendAddressPool $backend `
    -Probe $probe -LoadBalancingRule $rule
$backendPool = $lb.BackendAddressPools | Where-Object Name -EQ 'pool-web'

# 6. Two network interfaces and Windows VMs
foreach ($vmName in $vmNames) {
    Write-Host "Creating $vmName ..." -ForegroundColor Cyan
    $nic = New-AzNetworkInterface -Name "nic-$vmName" -ResourceGroupName $rg `
        -Location $location -Subnet $subnet -NetworkSecurityGroup $nsg `
        -LoadBalancerBackendAddressPool $backendPool
    $vm = New-AzVMConfig -VMName $vmName -VMSize $vmSize
    $vm = Set-AzVMOperatingSystem -VM $vm -Windows -ComputerName $vmName `
        -Credential $credential -ProvisionVMAgent
    $vm = Set-AzVMSourceImage -VM $vm -PublisherName 'MicrosoftWindowsServer' `
        -Offer 'WindowsServer' -Skus '2022-datacenter-azure-edition' -Version 'latest'
    $vm = Add-AzVMNetworkInterface -VM $vm -Id $nic.Id -Primary
    New-AzVM -ResourceGroupName $rg -Location $location -VM $vm | Out-Null
}

# 7. Install IIS and customize the default home page on each VM
# Here-string is single-quoted so $env:COMPUTERNAME is evaluated inside each VM.
$iisScript = @'
$ErrorActionPreference = 'Stop'
Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
$computer = $env:COMPUTERNAME
$page = @"
<!DOCTYPE html>
<html><head><title>Azure Load Balancer Lab</title></head>
<body style="font-family:Arial;text-align:center;padding:75px">
<h1>Azure Load Balancer Demo</h1>
<h2>Server: $computer</h2>
<p>HTTP response served by IIS on $computer</p>
</body></html>
"@
Set-Content -Path 'C:\inetpub\wwwroot\index.html' -Value $page -Encoding UTF8
Set-Service -Name W3SVC -StartupType Automatic
Start-Service W3SVC -ErrorAction SilentlyContinue
(Get-Service W3SVC).Status
'@
foreach ($vmName in $vmNames) {
    Write-Host "Installing IIS on $vmName ..." -ForegroundColor Cyan
    $result = Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName $vmName `
        -CommandId 'RunPowerShellScript' -ScriptString $iisScript
    $result.Value | Select-Object Code,Message | Format-List
}

# 8. Find public URL
$ip = (Get-AzPublicIpAddress -ResourceGroupName $rg -Name 'pip-lb-web').IpAddress
$url = "http://$ip/"
Write-Host "`nLoad balancer URL: $url" -ForegroundColor Green

function Test-LB {
    param([string]$Url,[int]$Count=20)
    $results = @()
    for ($i=1; $i -le $Count; $i++) {
        try {
            # New connection on each request, as far as the HTTP client permits.
            $r = Invoke-WebRequest -Uri "$($Url)?request=$i" -DisableKeepAlive `
                 -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            $server = if ($r.Content -match 'Server:\s*(vm-web-\d+)') { $Matches[1] } else { 'Unknown' }
            Write-Host "Request $i -> $server (HTTP $($r.StatusCode))"
            $results += $server
        } catch {
            Write-Warning "Request $i failed: $($_.Exception.Message)"
        }
    }
    Write-Host "`nResponse counts:" -ForegroundColor Cyan
    $results | Group-Object | Select-Object Name,Count | Format-Table -AutoSize
}

# 9. Normal traffic test
Write-Host "`nTesting both healthy servers ..." -ForegroundColor Yellow
Test-LB -Url $url -Count 20

# 10. Failure test - stop IIS on VM1, then test after probes detect failure
Write-Host "`nStopping IIS on vm-web-01 ..." -ForegroundColor Yellow
Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName 'vm-web-01' `
    -CommandId 'RunPowerShellScript' -ScriptString 'Stop-Service W3SVC' | Out-Null
Start-Sleep -Seconds 30
Write-Host 'Failover test: new connections should reach vm-web-02' -ForegroundColor Yellow
Test-LB -Url $url -Count 10

# 11. Recovery test - restart IIS on VM1
Write-Host "`nRestarting IIS on vm-web-01 ..." -ForegroundColor Yellow
Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName 'vm-web-01' `
    -CommandId 'RunPowerShellScript' -ScriptString 'Start-Service W3SVC' | Out-Null
Start-Sleep -Seconds 30
Write-Host 'Recovery test: both servers are eligible again' -ForegroundColor Yellow
Test-LB -Url $url -Count 20

Write-Host "`nDemo finished. Browse: $url" -ForegroundColor Green
Write-Host "To delete resources after the class, run:" -ForegroundColor Yellow
Write-Host "Remove-AzResourceGroup -Name '$rg' -Force"
