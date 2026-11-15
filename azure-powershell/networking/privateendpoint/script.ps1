
# ============================================================
# AZURE PRIVATE ENDPOINT - SIMPLE HANDS-ON LAB
# Native Azure PowerShell
# ============================================================

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# 1. LOGIN AND VARIABLES
# ------------------------------------------------------------

Connect-AzAccount

$location = "centralindia"
$suffix = Get-Random -Minimum 100000 -Maximum 999999

$rg = "rg-privateendpoint-demo"
$vnetName = "vnet-demo"
$subnetName = "subnet-demo"
$vmName = "vm-demo"
$storageName = "stpe$suffix"
$containerName = "demo"

$vmUsername = "azureadmin"
$vmPassword = "AzureLab@2026Demo!"

$securePassword = ConvertTo-SecureString `
    $vmPassword -AsPlainText -Force

$credential = [PSCredential]::new(
    $vmUsername, $securePassword
)

# ------------------------------------------------------------
# 2. CREATE RESOURCE GROUP
# ------------------------------------------------------------

New-AzResourceGroup `
    -Name $rg `
    -Location $location

# ------------------------------------------------------------
# 3. CREATE VNET AND SUBNET
# ------------------------------------------------------------

$subnet = New-AzVirtualNetworkSubnetConfig `
    -Name $subnetName `
    -AddressPrefix "10.10.1.0/24"

$vnet = New-AzVirtualNetwork `
    -ResourceGroupName $rg `
    -Location $location `
    -Name $vnetName `
    -AddressPrefix "10.10.0.0/16" `
    -Subnet $subnet

$subnet = $vnet.Subnets[0]

# ------------------------------------------------------------
# 4. CREATE WINDOWS VM WITH PUBLIC IP
# ------------------------------------------------------------

$pip = New-AzPublicIpAddress `
    -ResourceGroupName $rg `
    -Location $location `
    -Name "pip-demo" `
    -Sku Standard `
    -AllocationMethod Static

$nic = New-AzNetworkInterface `
    -ResourceGroupName $rg `
    -Location $location `
    -Name "nic-demo" `
    -SubnetId $subnet.Id `
    -PublicIpAddressId $pip.Id

$vm = New-AzVMConfig `
    -VMName $vmName `
    -VMSize "Standard_B2s"

$vm = Set-AzVMOperatingSystem `
    -VM $vm `
    -Windows `
    -ComputerName $vmName `
    -Credential $credential `
    -ProvisionVMAgent

$vm = Set-AzVMSourceImage `
    -VM $vm `
    -PublisherName "MicrosoftWindowsServer" `
    -Offer "WindowsServer" `
    -Skus "2022-datacenter-azure-edition" `
    -Version "latest"

$vm = Add-AzVMNetworkInterface `
    -VM $vm `
    -Id $nic.Id

New-AzVM `
    -ResourceGroupName $rg `
    -Location $location `
    -VM $vm

# ------------------------------------------------------------
# 5. CREATE STORAGE ACCOUNT
# ------------------------------------------------------------

$storage = New-AzStorageAccount `
    -ResourceGroupName $rg `
    -Name $storageName `
    -Location $location `
    -SkuName "Standard_LRS" `
    -Kind "StorageV2" `
    -EnableHttpsTrafficOnly $true `
    -AllowBlobPublicAccess $false `
    -PublicNetworkAccess Enabled

Update-AzStorageAccountNetworkRuleSet `
    -ResourceGroupName $rg `
    -Name $storageName `
    -DefaultAction Allow

# ------------------------------------------------------------
# 6. CREATE CONTAINER AND UPLOAD FILE
# ------------------------------------------------------------

$ctx = $storage.Context

New-AzStorageContainer `
    -Name $containerName `
    -Context $ctx

$file = Join-Path $env:TEMP "test.txt"

"Hello from Azure Private Endpoint Lab" |
    Set-Content $file

Set-AzStorageBlobContent `
    -File $file `
    -Container $containerName `
    -Blob "test.txt" `
    -Context $ctx `
    -Force

# Generate read-only SAS URL
$sasUrl = New-AzStorageBlobSASToken `
    -Container $containerName `
    -Blob "test.txt" `
    -Permission r `
    -ExpiryTime (Get-Date).ToUniversalTime().AddHours(4) `
    -Context $ctx `
    -FullUri `
    -Protocol HttpsOnly

$storageHost = "$storageName.blob.core.windows.net"

# ------------------------------------------------------------
# 7. CONNECTIVITY TEST FUNCTIONS
# ------------------------------------------------------------

# Script that runs inside Azure VM
$vmTest = @'
param([string]$Url)

$storageHost = ([uri]$Url).Host

Write-Output "DNS RESULT:"
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

    Write-Output "VM SUCCESS: HTTP $($response.StatusCode)"
}
catch {
    Write-Output "VM FAILED:"
    Write-Output $_.Exception.Message
}
'@

$scriptPath = Join-Path $env:TEMP "vm-test.ps1"
$vmTest | Set-Content $scriptPath

function Test-VM {
    $result = Invoke-AzVMRunCommand `
        -ResourceGroupName $rg `
        -VMName $vmName `
        -CommandId "RunPowerShellScript" `
        -ScriptPath $scriptPath `
        -Parameter @{ Url = $sasUrl }

    $result.Value | ForEach-Object {
        Write-Host $_.Message
    }
}

function Test-Local {
    Write-Host "`nLOCAL DNS:"
    Resolve-DnsName $storageHost -Type A

    try {
        $response = Invoke-WebRequest `
            -Uri $sasUrl `
            -TimeoutSec 30

        Write-Host "LOCAL SUCCESS: HTTP $($response.StatusCode)"
    }
    catch {
        Write-Host "LOCAL FAILED: $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------
# 8. PHASE 1 - BEFORE PRIVATE ENDPOINT
# ------------------------------------------------------------

Write-Host "`nPHASE 1 - BEFORE PRIVATE ENDPOINT" `
    -ForegroundColor Yellow

Test-Local
Test-VM

# Expected:
# Local -> Public IP -> HTTP 200
# VM    -> Public IP -> HTTP 200

Read-Host "Press Enter to create Private Endpoint"

# ------------------------------------------------------------
# 9. CREATE PRIVATE ENDPOINT
# ------------------------------------------------------------

$connection = New-AzPrivateLinkServiceConnection `
    -Name "storage-connection" `
    -PrivateLinkServiceId $storage.Id `
    -GroupId "blob"

$pe = New-AzPrivateEndpoint `
    -ResourceGroupName $rg `
    -Location $location `
    -Name "pe-storage" `
    -Subnet $subnet `
    -PrivateLinkServiceConnection $connection

# Get Private Endpoint NIC and IP
$peNic = Get-AzNetworkInterface `
    -ResourceId $pe.NetworkInterfaces[0].Id

$privateIp = $peNic.IpConfigurations[0].PrivateIpAddress

Write-Host "Private Endpoint IP: $privateIp" `
    -ForegroundColor Green

# ------------------------------------------------------------
# 10. CONFIGURE PRIVATE DNS
# ------------------------------------------------------------

$dnsZoneName = "privatelink.blob.core.windows.net"

$dnsZone = New-AzPrivateDnsZone `
    -ResourceGroupName $rg `
    -Name $dnsZoneName

New-AzPrivateDnsVirtualNetworkLink `
    -ResourceGroupName $rg `
    -ZoneName $dnsZoneName `
    -Name "vnet-link" `
    -VirtualNetworkId $vnet.Id `
    -EnableRegistration:$false

$dnsConfig = New-AzPrivateDnsZoneConfig `
    -Name "blob-dns" `
    -PrivateDnsZoneId $dnsZone.ResourceId

New-AzPrivateDnsZoneGroup `
    -ResourceGroupName $rg `
    -PrivateEndpointName "pe-storage" `
    -Name "dns-zone-group" `
    -PrivateDnsZoneConfig $dnsConfig

# View private DNS A record
Get-AzPrivateDnsRecordSet `
    -ResourceGroupName $rg `
    -ZoneName $dnsZoneName `
    -RecordType A

# ------------------------------------------------------------
# 11. PHASE 2 - AFTER PRIVATE ENDPOINT
# ------------------------------------------------------------

Read-Host "Press Enter to test Private Endpoint"

Write-Host "`nPHASE 2 - PRIVATE ENDPOINT ENABLED" `
    -ForegroundColor Yellow

Test-VM
Test-Local

# Expected:
# VM    -> Private IP -> HTTP 200
# Local -> Public IP  -> HTTP 200

# ------------------------------------------------------------
# 12. DISABLE PUBLIC NETWORK ACCESS
# ------------------------------------------------------------

Read-Host "Press Enter to disable public network access"

Set-AzStorageAccount `
    -ResourceGroupName $rg `
    -Name $storageName `
    -PublicNetworkAccess Disabled

# ------------------------------------------------------------
# 13. PHASE 3 - FINAL TEST
# ------------------------------------------------------------

Read-Host "Press Enter to run final test"

Write-Host "`nPHASE 3 - PUBLIC ACCESS DISABLED" `
    -ForegroundColor Green

Test-Local
Test-VM

# Expected:
# Local -> HTTP 403
# VM    -> Private IP -> HTTP 200

# ------------------------------------------------------------
# 14. SUMMARY
# ------------------------------------------------------------

Write-Host "`nLAB COMPLETED" -ForegroundColor Green

Write-Host "Resource Group: $rg"
Write-Host "VM: $vmName"
Write-Host "Storage Account: $storageName"
Write-Host "Private Endpoint IP: $privateIp"
Write-Host "Private DNS Zone: $dnsZoneName"

# ------------------------------------------------------------
# 15. CLEANUP
# ------------------------------------------------------------

# Uncomment after class to delete all demo resources.
# Remove-AzResourceGroup -Name $rg -Force
