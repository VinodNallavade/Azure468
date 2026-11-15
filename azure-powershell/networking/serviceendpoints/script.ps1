
# ============================================================
# AZURE SERVICE ENDPOINT - COMPLETE HANDS-ON LAB
# Native Azure PowerShell (Az Module)
# ============================================================

$ErrorActionPreference = "Stop"

# ============================================================
# STEP 0 - LOGIN AND VARIABLES
# ============================================================

Connect-AzAccount

# Uncomment if you need to select a subscription
# Set-AzContext -SubscriptionId "<subscription-id>"

$location = "centralindia"
$suffix = Get-Random -Minimum 100000 -Maximum 999999

$rgName = "rg-serviceendpoint-demo"
$vnetName = "vnet-serviceendpoint"
$subnetName = "subnet-app"

$vmName = "vm-serviceendpoint"
$nicName = "nic-serviceendpoint"

$storageName = "stse$suffix"
$containerName = "demo"
$blobName = "test.txt"

# Hardcoded VM credentials - DEMO ONLY
$vmUsername = "azureadmin"
$vmPassword = "AzureLab@2026Demo!"

$securePassword = ConvertTo-SecureString `
    -String $vmPassword `
    -AsPlainText `
    -Force

$credential = [PSCredential]::new(
    $vmUsername,
    $securePassword
)

Write-Host "`nStarting Azure Service Endpoint Lab..." `
    -ForegroundColor Cyan


# ============================================================
# STEP 1 - CREATE RESOURCE GROUP
# ============================================================

Write-Host "`nSTEP 1: Creating Resource Group..." `
    -ForegroundColor Yellow

New-AzResourceGroup `
    -Name $rgName `
    -Location $location

Write-Host "Resource Group created successfully." `
    -ForegroundColor Green


# ============================================================
# STEP 2 - CREATE VNET AND SUBNET
# ============================================================

Write-Host "`nSTEP 2: Creating VNet and Subnet..." `
    -ForegroundColor Yellow

$subnetConfig = New-AzVirtualNetworkSubnetConfig `
    -Name $subnetName `
    -AddressPrefix "10.10.1.0/24"

$vnet = New-AzVirtualNetwork `
    -ResourceGroupName $rgName `
    -Location $location `
    -Name $vnetName `
    -AddressPrefix "10.10.0.0/16" `
    -Subnet $subnetConfig

Write-Host "VNet and Subnet created." `
    -ForegroundColor Green

# Verify that Service Endpoint is NOT enabled
Write-Host "`nCurrent Service Endpoints:"

$vnet.Subnets[0].ServiceEndpoints |
    Format-Table

Read-Host "Press Enter to continue to VM creation"


# ============================================================
# STEP 3 - CREATE WINDOWS VIRTUAL MACHINE
# ============================================================

Write-Host "`nSTEP 3: Creating Windows VM..." `
    -ForegroundColor Yellow

# Create NIC without public IP.
# VM Run Command will be used for testing.

$nic = New-AzNetworkInterface `
    -ResourceGroupName $rgName `
    -Location $location `
    -Name $nicName `
    -SubnetId $vnet.Subnets[0].Id

# Configure VM
$vmConfig = New-AzVMConfig `
    -VMName $vmName `
    -VMSize "Standard_B2s"

$vmConfig = Set-AzVMOperatingSystem `
    -VM $vmConfig `
    -Windows `
    -ComputerName $vmName `
    -Credential $credential `
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

New-AzVM `
    -ResourceGroupName $rgName `
    -Location $location `
    -VM $vmConfig

Write-Host "Windows VM created successfully." `
    -ForegroundColor Green

Read-Host "Press Enter to create Storage Account"


# ============================================================
# STEP 4 - CREATE STORAGE ACCOUNT
# ============================================================

Write-Host "`nSTEP 4: Creating Storage Account..." `
    -ForegroundColor Yellow

$storage = New-AzStorageAccount `
    -ResourceGroupName $rgName `
    -Name $storageName `
    -Location $location `
    -SkuName "Standard_LRS" `
    -Kind "StorageV2" `
    -EnableHttpsTrafficOnly $true `
    -AllowBlobPublicAccess $false `
    -PublicNetworkAccess Enabled

# Initially allow traffic from all networks
Update-AzStorageAccountNetworkRuleSet `
    -ResourceGroupName $rgName `
    -Name $storageName `
    -DefaultAction Allow

Write-Host "Storage Account created: $storageName" `
    -ForegroundColor Green


# ============================================================
# STEP 5 - CREATE CONTAINER AND UPLOAD TEST FILE
# ============================================================

Write-Host "`nSTEP 5: Creating Blob Container..." `
    -ForegroundColor Yellow

$ctx = $storage.Context

New-AzStorageContainer `
    -Name $containerName `
    -Context $ctx

# Create local test file
$testFile = Join-Path $env:TEMP "test.txt"

"Hello Students! Azure Service Endpoint Demo." |
    Set-Content -Path $testFile

# Upload file
Set-AzStorageBlobContent `
    -File $testFile `
    -Container $containerName `
    -Blob $blobName `
    -Context $ctx `
    -Force

Write-Host "Test blob uploaded successfully." `
    -ForegroundColor Green


# ============================================================
# STEP 6 - GENERATE SAS URL
# ============================================================

Write-Host "`nSTEP 6: Generating SAS URL..." `
    -ForegroundColor Yellow

$expiry = (Get-Date).ToUniversalTime().AddHours(4)

$sasUrl = New-AzStorageBlobSASToken `
    -Container $containerName `
    -Blob $blobName `
    -Permission r `
    -ExpiryTime $expiry `
    -Context $ctx `
    -FullUri `
    -Protocol HttpsOnly

Write-Host "SAS URL generated successfully."

# Do not print the SAS URL in public recordings.


# ============================================================
# STEP 7 - CREATE VM TEST SCRIPT
# ============================================================

# This script runs INSIDE the Windows VM.

$vmTestScript = @'
param([string]$Url)

Write-Output "==================================="
Write-Output "Testing Azure Storage from VM"
Write-Output "==================================="

$storageHost = ([uri]$Url).Host

Write-Output "Storage DNS Resolution:"

Resolve-DnsName $storageHost -Type A |
    Select-Object Name, IPAddress |
    Format-Table |
    Out-String |
    Write-Output

try {

    $response = Invoke-WebRequest `
        -Uri $Url `
        -UseBasicParsing `
        -TimeoutSec 30

    Write-Output "VM CONNECTION SUCCESSFUL"
    Write-Output "HTTP Status: $($response.StatusCode)"
    Write-Output "Blob Content: $($response.Content)"

}
catch {

    Write-Output "VM CONNECTION FAILED"
    Write-Output $_.Exception.Message

    if ($_.Exception.Response) {
        Write-Output "HTTP Status: $([int]$_.Exception.Response.StatusCode)"
    }

}
'@

$vmScriptPath = Join-Path `
    $env:TEMP `
    "Test-StorageFromVM.ps1"

$vmTestScript |
    Set-Content -Path $vmScriptPath -Encoding UTF8


# ============================================================
# STEP 8 - CREATE CONNECTIVITY TEST FUNCTIONS
# ============================================================

function Test-FromLocal {

    Write-Host "`nTesting Storage from LOCAL COMPUTER..." `
        -ForegroundColor Cyan

    try {

        $response = Invoke-WebRequest `
            -Uri $sasUrl `
            -TimeoutSec 30

        Write-Host "LOCAL CONNECTION SUCCESSFUL" `
            -ForegroundColor Green

        Write-Host "HTTP Status: $($response.StatusCode)"
        Write-Host $response.Content

    }
    catch {

        Write-Host "LOCAL CONNECTION FAILED" `
            -ForegroundColor Red

        Write-Host $_.Exception.Message

        if ($_.Exception.Response) {
            Write-Host "HTTP Status: $([int]$_.Exception.Response.StatusCode)"
        }

    }
}


function Test-FromVM {

    Write-Host "`nTesting Storage from AZURE VM..." `
        -ForegroundColor Cyan

    $result = Invoke-AzVMRunCommand `
        -ResourceGroupName $rgName `
        -VMName $vmName `
        -CommandId "RunPowerShellScript" `
        -ScriptPath $vmScriptPath `
        -Parameter @{ Url = $sasUrl }

    $result.Value | ForEach-Object {
        Write-Host $_.Message
    }
}


# ============================================================
# PHASE 1 - WITHOUT SERVICE ENDPOINT
# ============================================================

Write-Host "`n===================================="
Write-Host "PHASE 1 - WITHOUT SERVICE ENDPOINT"
Write-Host "====================================" `
    -ForegroundColor Yellow

# Get VNet
$vnet = Get-AzVirtualNetwork `
    -ResourceGroupName $rgName `
    -Name $vnetName

# Verify no endpoint
$vnet.Subnets[0].ServiceEndpoints

# TEST 1 - LOCAL
Test-FromLocal

# TEST 2 - AZURE VM
Test-FromVM

Write-Host "`nEXPECTED RESULTS:"
Write-Host "LOCAL COMPUTER : SUCCESS"
Write-Host "AZURE VM       : SUCCESS"

Read-Host "Press Enter to enable Service Endpoint"


# ============================================================
# PHASE 2 - ENABLE SERVICE ENDPOINT
# ============================================================

Write-Host "`n===================================="
Write-Host "PHASE 2 - ENABLE SERVICE ENDPOINT"
Write-Host "====================================" `
    -ForegroundColor Yellow

$vnet = Get-AzVirtualNetwork `
    -ResourceGroupName $rgName `
    -Name $vnetName

# Enable Microsoft.Storage Service Endpoint
Set-AzVirtualNetworkSubnetConfig `
    -VirtualNetwork $vnet `
    -Name $subnetName `
    -AddressPrefix "10.10.1.0/24" `
    -ServiceEndpoint "Microsoft.Storage"

# Apply changes
$vnet = Set-AzVirtualNetwork `
    -VirtualNetwork $vnet

# Verify
$subnet = $vnet.Subnets |
    Where-Object Name -eq $subnetName

Write-Host "`nEnabled Service Endpoints:"

$subnet.ServiceEndpoints |
    Format-Table Service, Locations

# Test again
Test-FromLocal
Test-FromVM

Write-Host "`nEXPECTED RESULTS:"
Write-Host "LOCAL COMPUTER : SUCCESS"
Write-Host "AZURE VM       : SUCCESS"

Write-Host "`nService Endpoint does not automatically block public access."

Read-Host "Press Enter to configure Storage firewall"


# ============================================================
# PHASE 3 - CONFIGURE STORAGE FIREWALL
# ============================================================

Write-Host "`n===================================="
Write-Host "PHASE 3 - RESTRICT STORAGE ACCESS"
Write-Host "====================================" `
    -ForegroundColor Yellow

# Allow subnet in Storage firewall
Add-AzStorageAccountNetworkRule `
    -ResourceGroupName $rgName `
    -Name $storageName `
    -VirtualNetworkResourceId $subnet.Id

# Deny other networks
Update-AzStorageAccountNetworkRuleSet `
    -ResourceGroupName $rgName `
    -Name $storageName `
    -DefaultAction Deny `
    -Bypass None

# Verify firewall
Get-AzStorageAccountNetworkRuleSet `
    -ResourceGroupName $rgName `
    -Name $storageName

# Verify public endpoint is still enabled
(Get-AzStorageAccount `
    -ResourceGroupName $rgName `
    -Name $storageName).PublicNetworkAccess

Write-Host "`nStorage firewall configured."
Write-Host "Allowed Subnet: $subnetName"
Write-Host "All other networks: Denied"

Write-Host "`nAllow a few minutes for firewall rules to propagate."

Read-Host "Press Enter to test connectivity"


# ============================================================
# PHASE 4 - TEST AFTER FIREWALL RESTRICTION
# ============================================================

Write-Host "`n===================================="
Write-Host "PHASE 4 - FINAL CONNECTIVITY TEST"
Write-Host "====================================" `
    -ForegroundColor Green

# LOCAL TEST
Test-FromLocal

# AZURE VM TEST
Test-FromVM

Write-Host "`nEXPECTED RESULTS:"
Write-Host "LOCAL COMPUTER : DENIED (HTTP 403)"
Write-Host "AZURE VM       : SUCCESS (HTTP 200)"


# ============================================================
# PHASE 5 - VERIFY EFFECTIVE ROUTES
# ============================================================

Write-Host "`n===================================="
Write-Host "PHASE 5 - CHECK EFFECTIVE ROUTES"
Write-Host "====================================" `
    -ForegroundColor Cyan

Get-AzEffectiveRouteTable `
    -NetworkInterfaceName $nicName `
    -ResourceGroupName $rgName |
    Format-Table `
        Source, `
        State, `
        AddressPrefix, `
        NextHopType `
        -AutoSize

Write-Host "`nLook for VirtualNetworkServiceEndpoint routes."


# ============================================================
# FINAL LAB SUMMARY
# ============================================================

Write-Host "`n===================================="
Write-Host "AZURE SERVICE ENDPOINT LAB COMPLETED"
Write-Host "====================================" `
    -ForegroundColor Green

Write-Host "Resource Group  : $rgName"
Write-Host "VNet            : $vnetName"
Write-Host "Subnet          : $subnetName"
Write-Host "Virtual Machine : $vmName"
Write-Host "Storage Account : $storageName"

Write-Host "`nKey Learning:"
Write-Host "1. VM can access Storage without Service Endpoint."
Write-Host "2. Service Endpoint enables subnet identity and routing."
Write-Host "3. Storage firewall controls allowed networks."
Write-Host "4. Local access is denied after subnet restriction."
Write-Host "5. VM continues accessing Storage through Azure backbone."


# ============================================================
# CLEANUP - RUN AFTER TRAINING
# ============================================================

# WARNING: Deletes the entire demo Resource Group.
# Uncomment only after completing the lab.

# Remove-AzResourceGroup `
#     -Name $rgName `
#     -Force
