
$location = "eastus"
$tenantId = "91f820e7-a557-448d-8ccf-c7452516ce24"
$tags = @{Environment="Production"; Owner="Vinod"}
﻿$resourcegroupname = "azrg-azlabs-eastus-4321"

$VnetName = "vnet-azlabs-eastus-0710"
$VnetAddressSpace = "10.1.1.0/29"
$SubnetName = "snet-azlabs-eastus-0710"

# Public IP Variables
$pipName = "pip-azlabs-eastus-0710"
$pipAllocationMethod = "Static"
$IpAddressVersion = "IPv4"
$Zone = 1,2,3

# NIC Variables
$nicName = "nic-azlabs-eastus-0710"

# NSG Variables
$nsgName = "nsg-azlabs-eastus-0710"

# NSG Rule Variables
$rdpRuleName = "Allow-RDP"

# VM Variables
$vmName = "vm-lab-eus-001"
$vmSize = "Standard_B2s"


Connect-AzAccount -TenantId $tenantId


# Create Resource Group
New-AzResourceGroup -Name $resourcegroupname -Location $location -Tag $tags -Force
Get-AzResourceGroup -Name $resourcegroupname


# VNET with Subnet built inline to fit your exact /29 constraint
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $VnetAddressSpace
$vnet = New-AzVirtualNetwork -ResourceGroupName $resourcegroupname -Location $location -AddressPrefix $VnetAddressSpace -Name $VnetName -Subnet $subnetConfig -Force


# PIP (Configured as Standard SKU to support Availability Zones)
$pip = New-AzPublicIpAddress -ResourceGroupName $resourcegroupname -Location $location -Name $pipName -AllocationMethod $pipAllocationMethod -IpAddressVersion $IpAddressVersion -Sku "Standard" -Zone $Zone -Force


# NSG & NSG Add rule of 3389 port for RDP access
$rdpRule = New-AzNetworkSecurityRuleConfig -Name $rdpRuleName -Description "Allow RDP access" -Access "Allow" -Protocol "Tcp" -Direction "Inbound" -Priority 1000 -SourceAddressPrefix "Internet" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourcegroupname -Location $location -Name $nsgName -SecurityRules $rdpRule


# NIC
$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName
$nic = New-AzNetworkInterface -ResourceGroupName $resourcegroupname -Location $location -Name $nicName -SubnetId $subnet.Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id -Force


# Create VM
# Note: This will securely prompt you in the console to type your desired local VM Admin username/password
$cred = Get-Credential 

$vmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize -Zone 3  | 
            Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential $cred | 
            Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-Datacenter" -Version "latest" | 
            Add-AzVMNetworkInterface -Id $nic.Id

New-AzVM -ResourceGroupName $resourcegroupname -Location $location -VM $vmConfig
