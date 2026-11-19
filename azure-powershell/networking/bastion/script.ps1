
# ==========================================
# AZURE BASTION - HANDS-ON LAB
# ==========================================

$ErrorActionPreference = "Stop"

$tenantId = "91f820e7-a557-448d-8ccf-c7452516ce24"
$tags = @{Environment="Production"; Owner="Vinod"}


Connect-AzAccount -TenantId $tenantId

# 2. Variables
$rgName       = "rg-bastion-demo"
$location     = "centralindia"
$vnetName     = "vnet-bastion-demo"
$vmName       = "vm-bastion-demo"
$bastionName  = "bastion-demo"
$publicIPName = "pip-bastion-demo"
$nsgName      = "nsg-bastion-workload"
$nicName      = "nic-bastion-vm"

# 3. Create Resource Group
New-AzResourceGroup `
    -Name $rgName `
    -Location $location

# 4. Create Subnets
$bastionSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "AzureBastionSubnet" `
    -AddressPrefix "10.10.0.0/26"

$workloadSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "snet-workload" `
    -AddressPrefix "10.10.1.0/24"

# 5. Create Virtual Network
$vnet = New-AzVirtualNetwork `
    -ResourceGroupName $rgName `
    -Location $location `
    -Name $vnetName `
    -AddressPrefix "10.10.0.0/16" `
    -Subnet $bastionSubnet,$workloadSubnet

# 6. Create NSG Rule for Bastion RDP
$rdpRule = New-AzNetworkSecurityRuleConfig `
    -Name "Allow-RDP-From-Bastion" `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 100 `
    -SourceAddressPrefix "10.10.0.0/26" `
    -SourcePortRange "*" `
    -DestinationAddressPrefix "*" `
    -DestinationPortRange 3389 `
    -Access Allow

$nsg = New-AzNetworkSecurityGroup `
    -ResourceGroupName $rgName `
    -Location $location `
    -Name $nsgName `
    -SecurityRules $rdpRule

# 7. Get Workload Subnet
$subnet = Get-AzVirtualNetworkSubnetConfig `
    -VirtualNetwork $vnet `
    -Name "snet-workload"

# 8. Create NIC without Public IP
$nic = New-AzNetworkInterface `
    -Name $nicName `
    -ResourceGroupName $rgName `
    -Location $location `
    -SubnetId $subnet.Id `
    -NetworkSecurityGroupId $nsg.Id

# 9. Get VM Credentials
$cred = Get-Credential -Message "Enter VM admin credentials"

# 10. Configure Windows VM
$vmConfig = New-AzVMConfig `
    -VMName $vmName `
    -VMSize "Standard_B2s"

$vmConfig = Set-AzVMOperatingSystem `
    -VM $vmConfig `
    -Windows `
    -ComputerName "bastionvm" `
    -Credential $cred `
    -ProvisionVMAgent `
    -EnableAutoUpdate

$vmConfig = Set-AzVMSourceImage `
    -VM $vmConfig `
    -PublisherName "MicrosoftWindowsServer" `
    -Offer "WindowsServer" `
    -Skus "2022-datacenter-azure-edition" `
    -Version "latest"

$vmConfig = Add-AzVMNetworkInterface `
    -VM $vmConfig `
    -Id $nic.Id

# 11. Deploy VM
New-AzVM `
    -ResourceGroupName $rgName `
    -Location $location `
    -VM $vmConfig

# 12. Create Public IP for Bastion
$bastionPIP = New-AzPublicIpAddress `
    -ResourceGroupName $rgName `
    -Name $publicIPName `
    -Location $location `
    -AllocationMethod Static `
    -Sku Standard

# 13. Deploy Azure Bastion
New-AzBastion `
    -ResourceGroupName $rgName `
    -Name $bastionName `
    -PublicIpAddress $bastionPIP `
    -VirtualNetworkId $vnet.Id `
    -Sku Basic

# 14. Validate VM Private IP
$vmNic = Get-AzNetworkInterface `
    -ResourceGroupName $rgName `
    -Name $nicName

Write-Host "VM Private IP:" `
    $vmNic.IpConfigurations[0].PrivateIpAddress

Write-Host "VM Public IP Count:" `
    $vmNic.IpConfigurations[0].PublicIpAddress

# 15. Validate Bastion
Get-AzBastion `
    -ResourceGroupName $rgName `
    -Name $bastionName

Write-Host "Deployment Complete"
