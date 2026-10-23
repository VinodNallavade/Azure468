
Connect-AzAccount


# Define settings
$resourceGroupName = "azrg-eastus-dev-23102026"
$location          = "eastus"
$storageAccountName = "azstreastusdev23102026" # Must be globally unique



New-AzResourceGroup -Name $resourceGroupName -Location $location

# Create the Storage Account
New-AzStorageAccount -ResourceGroupName $resourceGroupName `
                     -Name $storageAccountName `
                     -Location $location `
                     -SkuName Standard_LRS `
                     -Kind StorageV2
