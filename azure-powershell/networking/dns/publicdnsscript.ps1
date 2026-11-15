
# =====================================================
# AZURE PUBLIC DNS - HANDS-ON DEMO
# Native Azure PowerShell (Az Module)
# =====================================================

$ErrorActionPreference = "Stop"

# STEP 1 - LOGIN
Connect-AzAccount

# STEP 2 - VARIABLES
$rg = "rg-publicdns-demo"
$location = "centralindia"
$zoneName = "contoso.com"

# STEP 3 - CREATE RESOURCE GROUP
New-AzResourceGroup `
    -Name $rg `
    -Location $location

# STEP 4 - CREATE PUBLIC DNS ZONE
New-AzDnsZone `
    -Name $zoneName `
    -ResourceGroupName $rg

# STEP 5 - VIEW AZURE NAMESERVERS
$zone = Get-AzDnsZone `
    -Name $zoneName `
    -ResourceGroupName $rg

Write-Host "`nAzure DNS Nameservers:" -ForegroundColor Cyan
$zone.NameServers

Read-Host "Show nameservers in Azure Portal. Press Enter"

# STEP 6 - CREATE A RECORD
New-AzDnsRecordSet `
    -Name "www" `
    -RecordType A `
    -ZoneName $zoneName `
    -ResourceGroupName $rg `
    -Ttl 300 `
    -DnsRecords (
        New-AzDnsRecordConfig `
            -IPv4Address "20.50.10.15"
    )

# STEP 7 - CREATE CNAME RECORD
New-AzDnsRecordSet `
    -Name "app" `
    -RecordType CNAME `
    -ZoneName $zoneName `
    -ResourceGroupName $rg `
    -Ttl 300 `
    -DnsRecords (
        New-AzDnsRecordConfig `
            -Cname "www.contoso.com"
    )

# STEP 8 - CREATE TXT RECORD
New-AzDnsRecordSet `
    -Name "demo" `
    -RecordType TXT `
    -ZoneName $zoneName `
    -ResourceGroupName $rg `
    -Ttl 300 `
    -DnsRecords (
        New-AzDnsRecordConfig `
            -Value "Azure DNS Training"
    )

# STEP 9 - DISPLAY ALL DNS RECORDS
Write-Host "`nDNS Records:" -ForegroundColor Cyan

Get-AzDnsRecordSet `
    -ZoneName $zoneName `
    -ResourceGroupName $rg |
    Format-Table Name, RecordType, Ttl -AutoSize

Read-Host "Show DNS records in Azure Portal. Press Enter"

# STEP 10 - QUERY AZURE AUTHORITATIVE DNS
# This works without registrar delegation.

$azureNS = $zone.NameServers[0]

Write-Host "`nQuerying Azure DNS: $azureNS" `
    -ForegroundColor Yellow

Resolve-DnsName `
    -Name "www.contoso.com" `
    -Type A `
    -Server $azureNS

Resolve-DnsName `
    -Name "app.contoso.com" `
    -Type CNAME `
    -Server $azureNS

Resolve-DnsName `
    -Name "demo.contoso.com" `
    -Type TXT `
    -Server $azureNS

# STEP 11 - COMPARE WITH NORMAL DNS
Write-Host "`nNormal DNS Lookup:" `
    -ForegroundColor Yellow

Resolve-DnsName `
    -Name "www.contoso.com" `
    -Type A

# Important:
# This queries your configured DNS resolver.
# It does NOT necessarily query your new Azure zone.
# The answer may differ or the lookup may fail.

# STEP 12 - VIEW ZONE INFORMATION
Get-AzDnsZone `
    -Name $zoneName `
    -ResourceGroupName $rg |
    Format-List Name, NameServers, NumberOfRecordSets

# =====================================================
# CLEANUP - RUN AFTER CLASS
# =====================================================

# Remove-AzResourceGroup -Name $rg -Force
