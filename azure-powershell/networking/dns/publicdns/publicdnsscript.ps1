
# ============================================================
# AZURE PUBLIC DNS + WINDOWS VM + IIS
# Classroom Demonstration
# ============================================================

$ErrorActionPreference = "Stop"

# ----------------------------
# STEP 1: CONFIGURATION
# ----------------------------

$rg = "rg-publicdns-demo"
$location = "centralindia"

$vnetName = "vnet-dns-demo"
$subnetName = "subnet-web"
$nsgName = "nsg-dns-demo"
$pipName = "pip-dns-demo"
$nicName = "nic-dns-demo"
$vmName = "vm-dns-demo"

$zoneName = "contoso.com"
$recordName = "www"

$adminUsername = "azureadmin"

# Enter a strong VM password when prompted
$adminPassword = Read-Host `
    "Enter VM admin password" -AsSecureString

$credential = New-Object `
    System.Management.Automation.PSCredential `
    ($adminUsername, $adminPassword)

# ----------------------------
# STEP 2: LOGIN
# ----------------------------

Connect-AzAccount

# Select correct subscription if required
Get-AzContext

# ----------------------------
# STEP 3: RESOURCE GROUP
# ----------------------------

New-AzResourceGroup `
    -Name $rg `
    -Location $location

# ----------------------------
# STEP 4: NETWORK SECURITY GROUP
# ----------------------------

# Allow HTTP traffic for IIS
$httpRule = New-AzNetworkSecurityRuleConfig `
    -Name "Allow-HTTP" `
    -Description "Allow HTTP for DNS demo" `
    -Access Allow `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 100 `
    -SourceAddressPrefix Internet `
    -SourcePortRange "*" `
    -DestinationAddressPrefix "*" `
    -DestinationPortRange 80

$nsg = New-AzNetworkSecurityGroup `
    -ResourceGroupName $rg `
    -Location $location `
    -Name $nsgName `
    -SecurityRules $httpRule

# ----------------------------
# STEP 5: CREATE VNET + SUBNET
# ----------------------------

$subnet = New-AzVirtualNetworkSubnetConfig `
    -Name $subnetName `
    -AddressPrefix "10.10.1.0/24" `
    -NetworkSecurityGroup $nsg

$vnet = New-AzVirtualNetwork `
    -ResourceGroupName $rg `
    -Location $location `
    -Name $vnetName `
    -AddressPrefix "10.10.0.0/16" `
    -Subnet $subnet

# ----------------------------
# STEP 6: CREATE STATIC PUBLIC IP
# ----------------------------

$pip = New-AzPublicIpAddress `
    -ResourceGroupName $rg `
    -Location $location `
    -Name $pipName `
    -AllocationMethod Static `
    -Sku Standard `
    -IpAddressVersion IPv4

# ----------------------------
# STEP 7: CREATE NETWORK INTERFACE
# ----------------------------

$nic = New-AzNetworkInterface `
    -ResourceGroupName $rg `
    -Location $location `
    -Name $nicName `
    -SubnetId $vnet.Subnets[0].Id `
    -PublicIpAddressId $pip.Id

# ----------------------------
# STEP 8: CREATE WINDOWS VM
# ----------------------------

$vm = New-AzVMConfig `
    -VMName $vmName `
    -VMSize "Standard_B2s"

$vm = Set-AzVMOperatingSystem `
    -VM $vm `
    -Windows `
    -ComputerName $vmName `
    -Credential $credential `
    -ProvisionVMAgent `
    -EnableAutoUpdate

$vm = Set-AzVMSourceImage `
    -VM $vm `
    -PublisherName "MicrosoftWindowsServer" `
    -Offer "WindowsServer" `
    -Skus "2022-datacenter-azure-edition" `
    -Version "latest"

$vm = Add-AzVMNetworkInterface `
    -VM $vm `
    -Id $nic.Id

New-AzVM `
    -ResourceGroupName $rg `
    -Location $location `
    -VM $vm

# ----------------------------
# STEP 9: INSTALL IIS
# ----------------------------

$iisScript = @'
Install-WindowsFeature -Name Web-Server -IncludeManagementTools

$html = @"
<!DOCTYPE html>
<html>
<head>
<title>Azure DNS Demo</title>
<style>
body {
  font-family: Arial;
  background: #eef6ff;
  text-align: center;
  padding: 80px;
}
h1 { color: #0078D4; }
</style>
</head>
<body>
<h1>Welcome to Azure Public DNS Demo!</h1>
<h2>This website is hosted on an Azure Windows VM</h2>
<p>DNS resolves the hostname to the VM's public IP.</p>
</body>
</html>
"@

Set-Content `
    -Path "C:\inetpub\wwwroot\index.html" `
    -Value $html

Start-Service W3SVC
'@

Invoke-AzVMRunCommand `
    -ResourceGroupName $rg `
    -VMName $vmName `
    -CommandId "RunPowerShellScript" `
    -ScriptString $iisScript

# ----------------------------
# STEP 10: GET ACTUAL PUBLIC IP
# ----------------------------

$pip = Get-AzPublicIpAddress `
    -ResourceGroupName $rg `
    -Name $pipName

$publicIP = $pip.IpAddress

Write-Host "`nVM Public IP: $publicIP" `
    -ForegroundColor Green

# Test the website directly by IP
Write-Host "Website URL: http://$publicIP"

Read-Host "Open the website by IP. Press Enter to continue"

# ----------------------------
# STEP 11: CREATE PUBLIC DNS ZONE
# ----------------------------

New-AzDnsZone `
    -Name $zoneName `
    -ResourceGroupName $rg

# ----------------------------
# STEP 12: CREATE DNS A RECORD
# ----------------------------

New-AzDnsRecordSet `
    -Name $recordName `
    -RecordType A `
    -ZoneName $zoneName `
    -ResourceGroupName $rg `
    -Ttl 300 `
    -DnsRecords (
        New-AzDnsRecordConfig `
            -IPv4Address $publicIP
    )

# ----------------------------
# STEP 13: GET AZURE NAMESERVERS
# ----------------------------

$zone = Get-AzDnsZone `
    -Name $zoneName `
    -ResourceGroupName $rg

Write-Host "`nAzure DNS Nameservers:" `
    -ForegroundColor Cyan

$zone.NameServers

# ----------------------------
# STEP 14: VERIFY DNS RECORD
# ----------------------------

Write-Host "`nCreated DNS A Record:" `
    -ForegroundColor Cyan

Get-AzDnsRecordSet `
    -Name $recordName `
    -RecordType A `
    -ZoneName $zoneName `
    -ResourceGroupName $rg

# ----------------------------
# STEP 15: QUERY AZURE DNS DIRECTLY
# ----------------------------

# Query the authoritative Azure DNS server.
# This does not require registrar delegation.

$azureNS = $zone.NameServers[0]

Write-Host "`nQuerying Azure DNS: $azureNS" `
    -ForegroundColor Yellow

Resolve-DnsName `
    -Name "www.$zoneName" `
    -Type A `
    -Server $azureNS

# ----------------------------
# STEP 16: COMPARE NORMAL DNS
# ----------------------------

# This query uses your computer's configured
# recursive DNS resolver.
#
# It will not necessarily use the Azure DNS zone
# until the domain is delegated to Azure.

Resolve-DnsName `
    -Name "www.$zoneName" `
    -Type A

# ----------------------------
# STEP 17: FINAL OUTPUT
# ----------------------------

Write-Host "`n========== DEMO SUMMARY ==========" `
    -ForegroundColor Cyan

Write-Host "VM Name       : $vmName"
Write-Host "Public IP     : $publicIP"
Write-Host "Website       : http://$publicIP"
Write-Host "DNS Zone      : $zoneName"
Write-Host "DNS Record    : www.$zoneName"
Write-Host "Azure DNS NS  : $azureNS"

Write-Host "`nDNS demonstration complete!" `
    -ForegroundColor Green

# ============================================================
# CLEANUP - RUN ONLY AFTER THE CLASS
# ============================================================

# Remove-AzResourceGroup -Name $rg -Force
