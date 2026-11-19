
# ==========================================
# Azure Point-to-Site VPN Gateway Lab
# Requires Az PowerShell module
# ==========================================

$tenantId = "91f820e7-a557-448d-8ccf-c7452516ce24"
$tags = @{Environment="Production"; Owner="Vinod"}


Connect-AzAccount -TenantId $tenantId

# Variables
$location = "centralindia"
$rgName = "rg-vpn-lab"
$vnetName = "vnet-vpn-lab"
$gatewayName = "vgw-p2s-lab"
$publicIpName = "pip-vpn-gateway"

# 1. Create Resource Group
New-AzResourceGroup `
    -Name $rgName `
    -Location $location

# 2. Create Subnets
$vmSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "snet-vm" `
    -AddressPrefix "10.10.1.0/24"

$gatewaySubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "GatewaySubnet" `
    -AddressPrefix "10.10.255.0/27"

# 3. Create Virtual Network
$vnet = New-AzVirtualNetwork `
    -Name $vnetName `
    -ResourceGroupName $rgName `
    -Location $location `
    -AddressPrefix "10.10.0.0/16" `
    -Subnet $vmSubnet,$gatewaySubnet

# 4. Create Public IP
$pip = New-AzPublicIpAddress `
    -Name $publicIpName `
    -ResourceGroupName $rgName `
    -Location $location `
    -AllocationMethod Static `
    -Sku Standard `
    -Zone 1,2,3

# 5. Get Gateway Subnet
$subnet = Get-AzVirtualNetworkSubnetConfig `
    -Name "GatewaySubnet" `
    -VirtualNetwork $vnet

# 6. Create Gateway IP Configuration
$ipConfig = New-AzVirtualNetworkGatewayIpConfig `
    -Name "vpn-ipconfig" `
    -SubnetId $subnet.Id `
    -PublicIpAddressId $pip.Id

# 7. Create VPN Gateway
$gateway = New-AzVirtualNetworkGateway `
    -Name $gatewayName `
    -ResourceGroupName $rgName `
    -Location $location `
    -IpConfigurations $ipConfig `
    -GatewayType Vpn `
    -VpnType RouteBased `
    -GatewaySku VpnGw1AZ

# 8. Create Root Certificate (Windows)
$rootCert = New-SelfSignedCertificate `
    -Type Custom `
    -KeySpec Signature `
    -Subject "CN=AzureP2SRoot" `
    -KeyExportPolicy Exportable `
    -HashAlgorithm sha256 `
    -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyUsageProperty Sign `
    -KeyUsage CertSign

# 9. Export Public Root Certificate
$certPath = Join-Path $env:TEMP "AzureP2SRoot.cer"

Export-Certificate `
    -Cert $rootCert `
    -FilePath $certPath | Out-Null

# 10. Convert Certificate to Base64
$certData = [Convert]::ToBase64String(
    [System.IO.File]::ReadAllBytes($certPath)
)

# 11. Configure P2S VPN
$vpnClientRootCert = New-AzVpnClientRootCertificate `
    -Name "AzureP2SRoot" `
    -PublicCertData $certData

Set-AzVirtualNetworkGateway `
    -VirtualNetworkGateway $gateway `
    -VpnClientAddressPool "172.16.0.0/24" `
    -VpnClientProtocol OpenVPN `
    -VpnClientRootCertificates $vpnClientRootCert

Write-Host "P2S VPN Gateway configured successfully"




$rootCert = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object {
        $_.Subject -eq "CN=AzureP2SRoot"
    } |
    Select-Object -First 1

$clientCert = New-SelfSignedCertificate `
    -Type Custom `
    -DnsName "AzureVPNClient" `
    -KeySpec Signature `
    -Subject "CN=AzureVPNClient" `
    -Signer $rootCert `
    -KeyExportPolicy Exportable `
    -HashAlgorithm sha256 `
    -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @(
        "2.5.29.37={text}1.3.6.1.5.5.7.3.2"
    )

Write-Host "Client certificate created"




$gateway = Get-AzVirtualNetworkGateway `
    -Name "vgw-p2s-lab" `
    -ResourceGroupName "rg-vpn-lab"

$vpnProfile = New-AzVpnClientConfiguration `
    -ResourceGroupName "rg-vpn-lab" `
    -Name "vgw-p2s-lab" `
    -AuthenticationMethod "EapTls"

$vpnProfile.VPNProfileSASUrl
