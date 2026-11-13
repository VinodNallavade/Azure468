# 02-enable-nva.ps1
# Turns vm2-dmz into an NVA (a router) and adds routes so that
# VM1 -> VM3 traffic must pass through VM2.

$rg       = "rg-udr-demo"
$location = "centralindia"

# ---- 1. Azure side: allow IP forwarding on VM2's network card ----
$nic2 = Get-AzNetworkInterface -ResourceGroupName $rg -Name "nic-vm2"
$nic2.EnableIPForwarding = $true
Set-AzNetworkInterface -NetworkInterface $nic2

# ---- 2. Windows side: turn on IP forwarding inside VM2 ----
# (You can also paste this line into PowerShell on VM2 yourself)
Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName "vm2-dmz" -CommandId RunPowerShellScript `
    -ScriptString 'Get-NetIPInterface -AddressFamily IPv4 | Set-NetIPInterface -Forwarding Enabled'

# ---- 3. Route table for the public subnet: to reach 10.0.3.0/24 go via VM2 ----
$rtPublic = New-AzRouteTable -ResourceGroupName $rg -Location $location -Name "rt-public"
Add-AzRouteConfig -RouteTable $rtPublic -Name "to-private-via-dmz" -AddressPrefix "10.0.3.0/24" `
    -NextHopType VirtualAppliance -NextHopIpAddress "10.0.2.4"
Set-AzRouteTable -RouteTable $rtPublic

# ---- 4. Route table for the private subnet: replies to 10.0.1.0/24 also go via VM2 ----
$rtPrivate = New-AzRouteTable -ResourceGroupName $rg -Location $location -Name "rt-private"
Add-AzRouteConfig -RouteTable $rtPrivate -Name "to-public-via-dmz" -AddressPrefix "10.0.1.0/24" `
    -NextHopType VirtualAppliance -NextHopIpAddress "10.0.2.4"
Set-AzRouteTable -RouteTable $rtPrivate

# ---- 5. Attach the route tables to the subnets ----
# (The DMZ subnet gets NO route table, otherwise VM2 would loop traffic back to itself)
$vnet = Get-AzVirtualNetwork -ResourceGroupName $rg -Name "vnet-udr-demo"
$vnet.Subnets[0].RouteTable = $rtPublic      # snet-public
$vnet.Subnets[2].RouteTable = $rtPrivate     # snet-private
Set-AzVirtualNetwork -VirtualNetwork $vnet

# ---- Done ----
Write-Host "Wait about 30 seconds, then on VM1 run again:  tracert -d 10.0.3.4"
Write-Host "Expected: hop 1 = 10.0.2.4 (DMZ), hop 2 = 10.0.3.4"