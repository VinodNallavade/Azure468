# 1. Define your variables
$rgName       = "azrg-networkingdemo-001"
$location     = "eastus"
$vnetName     = "vnet-001"
$subnetName   = "websubnet"
$asgName      = "azasg-eastus-001"
$nicName      = "nic-web002"
$vmName       = "web002"

# Create credential object with a dummy password (must meet Azure complexity rules)
$username     = "azureadmin"
$password     = ConvertTo-SecureString "P@ssw0rd1234!" -AsPlainText -Force
$cred         = New-Object System.Management.Automation.PSCredential ($username, $password)

# 2. Retrieve the existing Virtual Network and Subnet
$vnet   = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName
$subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet

# 3. Create the Application Security Group (or use Get-AzApplicationSecurityGroup if it exists)
#$asg = New-AzApplicationSecurityGroup -ResourceGroupName $rgName -Name $asgName -Location $location

$asg = Get-AzApplicationSecurityGroup -ResourceGroupName $rgName -Name $asgName


# 4. Create the NIC and attach the ASG to it
$nic = New-AzNetworkInterface `
    -Name $nicName `
    -ResourceGroupName $rgName `
    -Location $location `
    -Subnet $subnet `
    -ApplicationSecurityGroup $asg

# 5. Build the VM configuration and attach the pre-configured NIC
$vmConfig = New-AzVMConfig -VMName $vmName -VMSize "Standard_B2s" |
    Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential $cred |
    Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" |
    Add-AzVMNetworkInterface -Id $nic.Id

# 6. Deploy the VM
New-AzVM -ResourceGroupName $rgName -Location $location -VM $vmConfig
