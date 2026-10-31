#Install-Module -Name AzTable -Repository PSGallery -Scope CurrentUser
#Import-Module -Name AzTable


# 2. Configuration & Authentication context
$ResourceGroupName = "azrg-eastus-dev-23102026"
$StorageAccountName = "azstreastusdev23102026"
$TableName = "Orders"

$ctx = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
$CloudTable = (Get-AzStorageTable -Name $TableName -Context $ctx.Context -ErrorAction SilentlyContinue).CloudTable
if ($null -eq $CloudTable) {
    $CloudTable = (New-AzStorageTable -Name $TableName -Context $ctx.Context).CloudTable
}

# 3. Structural keys for indexing
$CustomerId = "CUST-98765"
$OrderId    = "ORD-2026-1031-8842"  # Scalable unique ID format

# 4. Complex sub-structures (Line Items & Shipping Address)
$LineItems = @(
    @{ SKU = "LAP-DELL-XPS13"; Description = "Dell XPS 13 Laptop"; Quantity = 1; UnitPrice = 1199.99; Total = 1199.99 }
    @{ SKU = "MOU-LOGI-MX3";   Description = "Logitech MX Master 3"; Quantity = 2; UnitPrice = 99.99;  Total = 199.98 }
)

$ShippingAddress = @{
    Street     = "123 Technology Drive"
    Suite      = "Suite 400"
    City       = "Austin"
    State      = "TX"
    PostalCode = "78701"
    Country    = "US"
}

# 5. Flatten the complex objects to JSON strings so Azure Table can store them
$LineItemsJson = $LineItems | ConvertTo-Json -Compress
$ShippingAddressJson = $ShippingAddress | ConvertTo-Json -Compress

# 6. Assemble the final production-ready table properties
$OrderProperties = @{
    # Financial metrics
    SubTotal         = 1399.97
    TaxAmount        = 115.50
    ShippingFee      = 15.00
    TotalAmount      = 1530.47
    Currency         = "USD"

    # Status & Metadata
    OrderStatus      = "PendingPayment"
    PaymentMethod    = "CreditCard"
    ShippingProvider = "FedEx"
    TrackingNumber   = "FX-99882211-US"
    
    # Packed structural columns (Serialized JSON strings)
    OrderItems       = $LineItemsJson
    ShippingAddress  = $ShippingAddressJson
    
    # Dates
    CreatedAt        = (Get-Date).ToUniversalTime()
    UpdatedAt        = (Get-Date).ToUniversalTime()
}

# 7. Write data to Azure Table Storage
try {
    Add-AzTableRow `
        -table $CloudTable `
        -partitionKey $CustomerId `
        -rowKey $OrderId `
        -property $OrderProperties | Out-Null

    Write-Host "[Success] Real-world order row inserted!" -ForegroundColor Green
    Write-Host "PartitionKey (Customer): $CustomerId" -ForegroundColor Gray
    Write-Host "RowKey (Order Number)   : $OrderId" -ForegroundColor Gray
}
catch {
    Write-Error "Failed to add structural order row: $_"
}
