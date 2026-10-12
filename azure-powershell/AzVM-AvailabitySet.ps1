# ---------------- Variables ----------------
$location          = "eastus"
$tenantId          = "91f820e7-a557-448d-8ccf-c7452516ce24"
$tags              = @{Environment="Production"; Owner="Vinod"}
$resourcegroupname = "azrg-azlabs-1210"
$AvSet             = "azaset-azlabs-eastus-002"

# Network
$VnetName          = "vnet-azlabs-eastus-0710"
$VnetAddressSpace  = "10.1.1.0/29"
$SubnetName        = "snet-azlabs-eastus-0710"

# Public IP
$pipName             = "pip-azlabs-eastus-0710"
$pipAllocationMethod = "Static"
$IpAddressVersion    = "IPv4"

# NIC / NSG
$nicName     = "nic-azlabs-eastus-0710"
$nsgName     = "nsg-azlabs-eastus-0710"
$rdpRuleName = "Allow-RDP"

# VM
$vmName  = "vm-lab-001"
$vmSize  = "Standard_B2s"
$vmCount = 3

# ---------------- Connect ----------------
Connect-AzAccount -TenantId $tenantId

# ---------------- Resource Group ----------------
New-AzResourceGroup -Name $resourcegroupname -Location $location -Tag $tags -Force
Get-AzResourceGroup -Name $resourcegroupname

# ---------------- VNet + Subnet ----------------
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $VnetAddressSpace
$vnet = New-AzVirtualNetwork -ResourceGroupName $resourcegroupname -Location $location `
          -Name $VnetName -AddressPrefix $VnetAddressSpace -Subnet $subnetConfig -Force

# ---------------- NSG + RDP rule ----------------
# SECURITY: replace "Internet" with your own public IP/32 where possible
$rdpRule = New-AzNetworkSecurityRuleConfig -Name $rdpRuleName -Description "Allow RDP access" `
             -Access Allow -Protocol Tcp -Direction Inbound -Priority 1000 `
             -SourceAddressPrefix "Internet" -SourcePortRange "*" `
             -DestinationAddressPrefix "*" -DestinationPortRange 3389

$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourcegroupname -Location $location `
         -Name $nsgName -SecurityRules $rdpRule

# ---------------- Subnet reference ----------------
$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName

# ---------------- Availability Set (managed disks) ----------------
$avSetDetails = New-AzAvailabilitySet -ResourceGroupName $resourcegroupname `
                  -Name $AvSet `
                  -Location $location `
                  -PlatformFaultDomainCount 2 `
                  -PlatformUpdateDomainCount 5 `
                  -Sku Aligned

# ---------------- Credentials ----------------
$cred = Get-Credential

# ---------------- Create VMs in the Availability Set ----------------
foreach ($i in 1..$vmCount)
{
    # Standard SKU public IP (no zone, since VMs are in an availability set)
    $pip = New-AzPublicIpAddress -ResourceGroupName $resourcegroupname -Location $location `
             -Name "$pipName-$i" -AllocationMethod $pipAllocationMethod `
             -IpAddressVersion $IpAddressVersion -Sku Standard -Force

    $nic = New-AzNetworkInterface -ResourceGroupName $resourcegroupname -Location $location `
             -Name "$nicName-$i" -SubnetId $subnet.Id `
             -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id -Force

    $vmConfig = New-AzVMConfig -VMName "$vmName-$i" -VMSize $vmSize -AvailabilitySetId $avSetDetails.Id |
                Set-AzVMOperatingSystem -Windows -ComputerName "$vmName-$i" -Credential $cred |
                Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" `
                                    -Skus "2022-datacenter-g2" -Version "latest" |
                Add-AzVMNetworkInterface -Id $nic.Id

    New-AzVM -ResourceGroupName $resourcegroupname -Location $location -VM $vmConfig
}