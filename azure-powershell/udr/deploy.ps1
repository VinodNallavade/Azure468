# 01-deploy.ps1
# Builds: 1 VNet, 3 subnets (public, dmz, private) and 3 Windows VMs.
# No routes yet, so VM1 -> VM3 goes directly.
# Needs the Az module. Run in PowerShell or Azure Cloud Shell.

# ---- Settings ----
$rg       = "rg-udr-demo"
$location = "centralindia"
$user     = "azureadmin"
$password = "Demo@Pass12345!"      # demo password only
$myIp     = "*"                    # better: put your public IP here, like 1.2.3.4/32

Connect-AzAccount -Tenant "91f820e7-a557-448d-8ccf-c7452516ce24" -Subscription "VinodNallavade"
# ---- 1. Resource group ----
New-AzResourceGroup -Name $rg -Location $location

# ---- 2. NSG that allows RDP (so we can log in to VM1) ----
$rdp = New-AzNetworkSecurityRuleConfig -Name "Allow-RDP" -Priority 100 -Direction Inbound `
       -Access Allow -Protocol Tcp -SourceAddressPrefix $myIp -SourcePortRange * `
       -DestinationAddressPrefix * -DestinationPortRange 3389
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $location -Name "nsg-public" -SecurityRules $rdp

# ---- 3. VNet with 3 subnets ----
$subPublic  = New-AzVirtualNetworkSubnetConfig -Name "snet-public"  -AddressPrefix "10.0.1.0/24" -NetworkSecurityGroup $nsg
$subDmz     = New-AzVirtualNetworkSubnetConfig -Name "snet-dmz"     -AddressPrefix "10.0.2.0/24"
$subPrivate = New-AzVirtualNetworkSubnetConfig -Name "snet-private" -AddressPrefix "10.0.3.0/24"

$vnet = New-AzVirtualNetwork -ResourceGroupName $rg -Location $location -Name "vnet-udr-demo" `
        -AddressPrefix "10.0.0.0/16" -Subnet $subPublic, $subDmz, $subPrivate

# ---- 4. Public IP for VM1 (only VM1 gets one) ----
$pip = New-AzPublicIpAddress -ResourceGroupName $rg -Location $location -Name "pip-vm1" `
       -Sku Standard -AllocationMethod Static

# ---- 5. Network cards with fixed private IPs ----
$nic1 = New-AzNetworkInterface -ResourceGroupName $rg -Location $location -Name "nic-vm1" `
        -Subnet $vnet.Subnets[0] -PrivateIpAddress "10.0.1.4" -PublicIpAddress $pip
$nic2 = New-AzNetworkInterface -ResourceGroupName $rg -Location $location -Name "nic-vm2" `
        -Subnet $vnet.Subnets[1] -PrivateIpAddress "10.0.2.4"
$nic3 = New-AzNetworkInterface -ResourceGroupName $rg -Location $location -Name "nic-vm3" `
        -Subnet $vnet.Subnets[2] -PrivateIpAddress "10.0.3.4"

# ---- 6. Create the 3 Windows VMs (takes about 10-15 minutes) ----
$cred = New-Object System.Management.Automation.PSCredential($user, (ConvertTo-SecureString $password -AsPlainText -Force))

$vmNames = "vm1-public", "vm2-dmz", "vm3-private"
$nics    = $nic1, $nic2, $nic3

for ($i = 0; $i -lt 3; $i++) {
    $vmConfig = New-AzVMConfig -VMName $vmNames[$i] -VMSize "Standard_B2s" |
        Set-AzVMOperatingSystem -Windows -ComputerName $vmNames[$i] -Credential $cred |
        Set-AzVMSourceImage -PublisherName MicrosoftWindowsServer -Offer WindowsServer `
                            -Skus 2022-datacenter-azure-edition -Version latest |
        Add-AzVMNetworkInterface -Id $nics[$i].Id |
        Set-AzVMBootDiagnostic -Disable
    New-AzVM -ResourceGroupName $rg -Location $location -VM $vmConfig
}

# ---- 7. Allow ping (ICMP) in the Windows firewall of every VM ----
foreach ($name in $vmNames) {
    Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName $name -CommandId RunPowerShellScript `
        -ScriptString 'New-NetFirewallRule -DisplayName "Allow ICMP" -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow'
}

# ---- Done ----
$ip = (Get-AzPublicIpAddress -ResourceGroupName $rg -Name "pip-vm1").IpAddress
Write-Host "RDP to VM1 at: $ip   user: $user   password: $password"
Write-Host "On VM1 open PowerShell and run:  tracert -d 10.0.3.4"