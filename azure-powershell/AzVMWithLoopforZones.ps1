
$location = "eastus"
$tenantId = "91f820e7-a557-448d-8ccf-c7452516ce24"
$tags = @{Environment="Production"; Owner="Vinod"}
$resourcegroupname = "azrg-vmlab-eastus-0468"



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
$vmName = "vm-lab-001"
$vmSize = "Standard_B2s"
$zones = 1,2,3


Connect-AzAccount -TenantId $tenantId


# Create Resource Group
New-AzResourceGroup -Name $resourcegroupname -Location $location -Tag $tags -Force
Get-AzResourceGroup -Name $resourcegroupname


# VNET with Subnet built inline to fit your exact /29 constraint
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $VnetAddressSpace
$vnet = New-AzVirtualNetwork -ResourceGroupName $resourcegroupname -Location $location -AddressPrefix $VnetAddressSpace -Name $VnetName -Subnet $subnetConfig -Force


# NSG & NSG Add rule of 3389 port for RDP access
$rdpRule = New-AzNetworkSecurityRuleConfig -Name $rdpRuleName -Description "Allow RDP access" -Access "Allow" -Protocol "Tcp" -Direction "Inbound" -Priority 1000 -SourceAddressPrefix "Internet" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourcegroupname -Location $location -Name $nsgName -SecurityRules $rdpRule


# NIC
$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName


# Create VM
# Note: This will securely prompt you in the console to type your desired local VM Admin username/password
$cred = Get-Credential 




foreach($zonenumber in $zones)
{


# PIP (Configured as Standard SKU to support Availability Zones)
$pip = New-AzPublicIpAddress -ResourceGroupName $resourcegroupname -Location $location -Name "$pipName-$zonenumber" -AllocationMethod $pipAllocationMethod -IpAddressVersion $IpAddressVersion -Sku "Standard" -Zone $Zone -Force

$nic = New-AzNetworkInterface -ResourceGroupName $resourcegroupname -Location $location -Name "$nicName-$zonenumber" -SubnetId $subnet.Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id -Force

$vmConfig = New-AzVMConfig -VMName "$vmName-$zonenumber" -VMSize $vmSize -Zone $zonenumber  | 
            Set-AzVMOperatingSystem -Windows -ComputerName "$vmName-$zonenumber" -Credential $cred | 
            Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-Datacenter" -Version "latest" | 
            Add-AzVMNetworkInterface -Id $nic.Id

New-AzVM -ResourceGroupName $resourcegroupname -Location $location -VM $vmConfig

}
