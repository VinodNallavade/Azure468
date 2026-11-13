# REGIONAL VNet peering demo - both VNets and VMs in the SAME region
# Requires Az module:  Install-Module Az -Scope CurrentUser

# ---------- Settings ----------
$rg       = "rg-peering-regional-demo"
$location = "centralindia"
$vmSize   = "Standard_B2s"

$username = "azureadmin"
$password = "P@ssw0rd12345!"
$cred = New-Object System.Management.Automation.PSCredential($username, (ConvertTo-SecureString $password -AsPlainText -Force))

# ---------- Login ----------
Connect-AzAccount

# ---------- Resource group ----------
New-AzResourceGroup -Name $rg -Location $location

# ---------- VNet A + VM A ----------
$subnetA = New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.1.1.0/24"
$vnetA   = New-AzVirtualNetwork -Name "vnet-a" -ResourceGroupName $rg -Location $location -AddressPrefix "10.1.0.0/16" -Subnet $subnetA
$nicA    = New-AzNetworkInterface -Name "nic-a" -ResourceGroupName $rg -Location $location -SubnetId $vnetA.Subnets[0].Id

$vmA = New-AzVMConfig -VMName "vm-a" -VMSize $vmSize
$vmA = Set-AzVMOperatingSystem -VM $vmA -Windows -ComputerName "vm-a" -Credential $cred
$vmA = Set-AzVMSourceImage -VM $vmA -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest"
$vmA = Add-AzVMNetworkInterface -VM $vmA -Id $nicA.Id
$vmA = Set-AzVMBootDiagnostic -VM $vmA -Disable
New-AzVM -ResourceGroupName $rg -Location $location -VM $vmA

# ---------- VNet B + VM B (same region) ----------
$subnetB = New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.2.1.0/24"
$vnetB   = New-AzVirtualNetwork -Name "vnet-b" -ResourceGroupName $rg -Location $location -AddressPrefix "10.2.0.0/16" -Subnet $subnetB
$nicB    = New-AzNetworkInterface -Name "nic-b" -ResourceGroupName $rg -Location $location -SubnetId $vnetB.Subnets[0].Id

$vmB = New-AzVMConfig -VMName "vm-b" -VMSize $vmSize
$vmB = Set-AzVMOperatingSystem -VM $vmB -Windows -ComputerName "vm-b" -Credential $cred
$vmB = Set-AzVMSourceImage -VM $vmB -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest"
$vmB = Add-AzVMNetworkInterface -VM $vmB -Id $nicB.Id
$vmB = Set-AzVMBootDiagnostic -VM $vmB -Disable
New-AzVM -ResourceGroupName $rg -Location $location -VM $vmB

# ---------- Get private IPs ----------
$ipA = (Get-AzNetworkInterface -Name "nic-a" -ResourceGroupName $rg).IpConfigurations[0].PrivateIpAddress
$ipB = (Get-AzNetworkInterface -Name "nic-b" -ResourceGroupName $rg).IpConfigurations[0].PrivateIpAddress
Write-Host "VM-A: $ipA   VM-B: $ipB"

# ---------- Allow ping in Windows Firewall on both VMs ----------
$fw = 'New-NetFirewallRule -DisplayName "Allow ICMPv4" -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow'
Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName "vm-a" -CommandId "RunPowerShellScript" -ScriptString $fw
Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName "vm-b" -CommandId "RunPowerShellScript" -ScriptString $fw

# ---------- Ping BEFORE peering (should fail) ----------
Write-Host "BEFORE peering: VM-A pings VM-B (expect False)"
$r = Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName "vm-a" -CommandId "RunPowerShellScript" -ScriptString "Test-Connection -ComputerName $ipB -Count 2 -Quiet"
$r.Value[0].Message

# ---------- Create peering (both directions) ----------
Add-AzVirtualNetworkPeering -Name "peer-a-to-b" -VirtualNetwork $vnetA -RemoteVirtualNetworkId $vnetB.Id
Add-AzVirtualNetworkPeering -Name "peer-b-to-a" -VirtualNetwork $vnetB -RemoteVirtualNetworkId $vnetA.Id

Get-AzVirtualNetworkPeering -ResourceGroupName $rg -VirtualNetworkName "vnet-a" | Select-Object Name, PeeringState
Get-AzVirtualNetworkPeering -ResourceGroupName $rg -VirtualNetworkName "vnet-b" | Select-Object Name, PeeringState

# ---------- Ping AFTER peering (should work) ----------
Write-Host "AFTER peering: VM-A pings VM-B"
$r = Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName "vm-a" -CommandId "RunPowerShellScript" -ScriptString "Test-Connection -ComputerName $ipB -Count 4 | Format-Table Address, Latency, Status | Out-String"
$r.Value[0].Message

Write-Host "AFTER peering: VM-B pings VM-A"
$r = Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName "vm-b" -CommandId "RunPowerShellScript" -ScriptString "Test-Connection -ComputerName $ipA -Count 4 | Format-Table Address, Latency, Status | Out-String"
$r.Value[0].Message

# ---------- Cleanup (run this when you are done, VMs cost money) ----------
# Remove-AzResourceGroup -Name $rg -Force