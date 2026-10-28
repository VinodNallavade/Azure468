# Using Azure CLI to set a lifecycle management policy for a storage account

param(
	[Parameter(Mandatory = $true)]
	[string]$ResourceGroup,

	[Parameter(Mandatory = $true)]
	[string]$StorageAccount,

	[string]$PolicyFile = "D:\PersonnelWork\Azure468\Azure468\azure-powershell\policy.json"
)

if (-not (Test-Path -LiteralPath $PolicyFile -PathType Leaf)) {
	throw "Lifecycle policy file not found: $PolicyFile"
}

az storage account management-policy create `
	--account-name $StorageAccount `
	--policy "@$PolicyFile" `
	--resource-group $ResourceGroup

if ($LASTEXITCODE -ne 0) {
	throw "Failed to create the storage account lifecycle policy (az exited with code $LASTEXITCODE)."
}



# Using Powershell Az module to set a lifecycle management policy for a storage account
# Define the policy in JSON format
$jsonPolicy = @'
{
  "policy": {
    "rules": [
      {
        "enabled": true,
        "name": "DeleteOldBlobs",
        "type": "Lifecycle",
        "definition": {
          "actions": {
            "baseBlob": {
              "delete": {
                "daysAfterModificationGreaterThan": 180
              }
            }
          },
          "filters": {
            "blobTypes": [
              "blockBlob"
            ]
          }
        }
      }
    ]
  }
}
'@

# Apply the JSON policy
Set-AzStorageAccountManagementPolicy `
    -ResourceGroupName "myResourceGroup" `
    -StorageAccountName "mystorageaccount" `
    -Policy $jsonPolicy

