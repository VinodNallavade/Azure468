
    

$ErrorActionPreference = 'Stop'
$tenantId          = "91f820e7-a557-448d-8ccf-c7452516ce24"
$tags              = @{Environment="Production"; Owner="Vinod"}

# ---------- LAB SETTINGS ----------
$rg              = 'rg-lb-natv2-standalone'
$location        = 'centralindia'
$lbName          = 'lb-natv2-demo'
$poolName        = 'pool-web'
$vmNames         = @('vm-web-01','vm-web-02')
$vmSize          = 'Standard_B2s'
$adminUser       = 'azurelabadmin'
$adminPassword   = 'LabDemo!2026#Vm42'  # Change this before running; never use in production.
$frontendStart   = 50001
$frontendEnd     = 50010
# Optional override, especially for Azure Cloud Shell: e.g. '203.0.113.10/32'
$trustedPublicIp = ''

# ---------- SIGN IN / SAFETY CHECK ----------
if (-not (Get-Module -ListAvailable -Name Az.Network)) {
    throw 'Az.Network is not installed. Install-Module Az -Scope CurrentUser'
}
if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
      Connect-AzAccount -TenantId $tenantId 
}
Write-Host "Subscription: $((Get-AzContext).Subscription.Name)" -ForegroundColor Cyan
if (Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue) {
    throw "Resource group '$rg' already exists. Use a new name or delete the old disposable lab before rerunning."
}

# Detect public IP of the machine RUNNING this script. In Cloud Shell, override manually.
if ([string]::IsNullOrWhiteSpace($trustedPublicIp)) {
    $ip = [string](Invoke-RestMethod -Uri 'https://api4.ipify.org' -TimeoutSec 15)
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($ip.Trim(), [ref]$parsed) -or
        $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Could not identify a valid public IPv4 address: $ip"
    }
    $trustedPublicIp = "$($ip.Trim())/32"
}
Write-Host "RDP trusted source: $trustedPublicIp" -ForegroundColor Yellow
Write-Host 'If running in Cloud Shell, this is its egress IP (not your laptop). Set $trustedPublicIp manually.' -ForegroundColor Yellow

$secure = ConvertTo-SecureString $adminPassword -AsPlainText -Force
$cred = [pscredential]::new($adminUser, $secure)

# ---------- RESOURCE GROUP / NETWORK ----------
New-AzResourceGroup -Name $rg -Location $location | Out-Null
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name 'subnet-web' -AddressPrefix '10.20.1.0/24'
$vnet = New-AzVirtualNetwork -ResourceGroupName $rg -Location $location `
    -Name 'vnet-natv2-demo' -AddressPrefix '10.20.0.0/16' -Subnet $subnetConfig
$subnet = $vnet.Subnets[0]

# Important: backend NSG sees translated destination TCP 3389, NOT port 50001.
$rules = @(
    (New-AzNetworkSecurityRuleConfig -Name 'Allow-HTTP' -Protocol Tcp `
        -Direction Inbound -Priority 100 -Access Allow -SourceAddressPrefix Internet `
        -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange 80),
    (New-AzNetworkSecurityRuleConfig -Name 'Allow-RDP-Trusted-IP' -Protocol Tcp `
        -Direction Inbound -Priority 110 -Access Allow -SourceAddressPrefix $trustedPublicIp `
        -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange 3389),
    (New-AzNetworkSecurityRuleConfig -Name 'Allow-LB-Health-Probe' -Protocol Tcp `
        -Direction Inbound -Priority 120 -Access Allow -SourceAddressPrefix AzureLoadBalancer `
        -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange 80)
)
$nsg = New-AzNetworkSecurityGroup -Name 'nsg-web' -ResourceGroupName $rg `
    -Location $location -SecurityRules $rules

# ---------- LOAD BALANCER / NAT V2 ----------
$pip = New-AzPublicIpAddress -Name 'pip-natv2-demo' -ResourceGroupName $rg `
    -Location $location -Sku Standard -AllocationMethod Static
$fe = New-AzLoadBalancerFrontendIpConfig -Name 'frontend-public' -PublicIpAddress $pip
$be = New-AzLoadBalancerBackendAddressPoolConfig -Name $poolName
$probe = New-AzLoadBalancerProbeConfig -Name 'probe-web' -Protocol Tcp -Port 80 `
    -IntervalInSeconds 5 -ProbeCount 2
$webRule = New-AzLoadBalancerRuleConfig -Name 'web-80' -Protocol Tcp `
    -FrontendPort 80 -BackendPort 80 -FrontendIpConfiguration $fe `
    -BackendAddressPool $be -Probe $probe -DisableOutboundSNAT

# ONE V2 rule assigns a distinct frontend port to each eligible backend VM.
$natV2 = New-AzLoadBalancerInboundNatRuleConfig -Name 'rdp-nat-v2' -Protocol Tcp `
    -FrontendIpConfiguration $fe -FrontendPortRangeStart $frontendStart `
    -FrontendPortRangeEnd $frontendEnd -BackendAddressPool $be -BackendPort 3389

$lb = New-AzLoadBalancer -Name $lbName -ResourceGroupName $rg -Location $location `
    -Sku Standard -FrontendIpConfiguration $fe -BackendAddressPool $be `
    -Probe $probe -LoadBalancingRule $webRule -InboundNatRule $natV2
$poolId = ($lb.BackendAddressPools | Where-Object Name -eq $poolName).Id

# ---------- CREATE TWO WINDOWS VMS ----------
foreach ($vmName in $vmNames) {
    Write-Host "Creating $vmName ..." -ForegroundColor Cyan
    $ipConfig = New-AzNetworkInterfaceIpConfig -Name 'ipconfig1' -SubnetId $subnet.Id `
        -LoadBalancerBackendAddressPoolId $poolId
    $nic = New-AzNetworkInterface -Name "nic-$vmName" -ResourceGroupName $rg `
        -Location $location -IpConfiguration $ipConfig -NetworkSecurityGroupId $nsg.Id
    $vm = New-AzVMConfig -VMName $vmName -VMSize $vmSize
    $vm = Set-AzVMOperatingSystem -VM $vm -Windows -ComputerName $vmName `
        -Credential $cred -ProvisionVMAgent
    $vm = Set-AzVMSourceImage -VM $vm -PublisherName MicrosoftWindowsServer `
        -Offer WindowsServer -Skus '2022-datacenter-azure-edition' -Version latest
    $vm = Add-AzVMNetworkInterface -VM $vm -Id $nic.Id
    New-AzVM -ResourceGroupName $rg -Location $location -VM $vm | Out-Null
}

# ---------- CONFIGURE IIS + RDP THROUGH VM RUN COMMAND ----------
$guestScript = @'
$ErrorActionPreference = 'Stop'
Install-WindowsFeature Web-Server -IncludeManagementTools | Out-Null
$computer = $env:COMPUTERNAME
$html = @"
<html><body style="font-family:Arial;text-align:center;padding:60px">
<h1>Azure Load Balancer Demo</h1>
<h2>Response from $computer</h2>
<p>Public web load balancing uses TCP 80.</p>
<p>Inbound NAT V2 uses a unique public port for RDP to each VM.</p>
</body></html>
"@
Set-Content -Path 'C:\inetpub\wwwroot\index.html' -Value $html
Set-Service W3SVC -StartupType Automatic
Start-Service W3SVC
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
    -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
Set-Service TermService -StartupType Automatic
Start-Service TermService
Write-Output "Configured IIS and RDP on $computer"
'@
foreach ($vmName in $vmNames) {
    Write-Host "Configuring IIS/RDP on $vmName ..." -ForegroundColor Cyan
    $result = Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName $vmName `
        -CommandId RunPowerShellScript -ScriptString $guestScript
    $result.Value | ForEach-Object { Write-Host $_.Message }
}

# ---------- TEST PUBLIC WEB ----------
$pip = Get-AzPublicIpAddress -ResourceGroupName $rg -Name 'pip-natv2-demo'
$publicIp = $pip.IpAddress
Write-Host "Testing Azure Load Balancer" -ForegroundColor Cyan
Write-Host "Website: http://$publicIp"

for ($i = 1; $i -le 12; $i++) {

    try {
        $response = Invoke-WebRequest `
            -Uri "http://$publicIp/?request=$i" `
            -UseBasicParsing `
            -DisableKeepAlive `
            -TimeoutSec 15 `
            -ErrorAction Stop

        if ($response.Content -match 'Response from ([\w-]+)') {
            $server = $Matches[1]
        }
        else {
            $server = "Server not identified"
        }

        Write-Host "Request $i -> $server" -ForegroundColor Green

    }
    catch {
        Write-Warning "Request $i failed: $($_.Exception.Message)"
    }

    Start-Sleep -Milliseconds 500
}

# ---------- NAT V2 PORT MAPPING ----------
Write-Host "`nNAT V2 configured: $frontendStart-$frontendEnd -> backend TCP 3389" -ForegroundColor Green
Write-Host 'To see actual per-VM port mappings:' -ForegroundColor Yellow
Write-Host "Azure Portal > Load Balancer > $lbName > Inbound NAT rules > rdp-nat-v2 > Port mapping"
Write-Host "Once assigned, connect with: mstsc.exe /v:$($publicIp):<assigned-port>"
Write-Host "Username: $adminUser"

