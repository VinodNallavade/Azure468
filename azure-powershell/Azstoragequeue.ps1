#Connect-AzAccount


# 1. Configuration variables
$ResourceGroupName = "azrg-eastus-dev-23102026"
$StorageAccountName = "azstreastusdev23102026"
$QueueName = "orderqueue"

# 2. Get the storage account context using Azure login details
$ctx = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
$StorageContext = $ctx.Context

# 3. Get a reference to the target queue (Creates it if it doesn't exist)
$Queue = Get-AzStorageQueue -Name $QueueName -Context $StorageContext -ErrorAction SilentlyContinue
if ($null -eq $Queue) {
    $Queue = New-AzStorageQueue -Name $QueueName -Context $StorageContext
    Write-Host "Created new queue: $QueueName" -ForegroundColor Cyan
}

# 4. Construct the order payload matching your C# structure
$OrderPayload = @{
    OrderId    = [Guid]::NewGuid().ToString()
    CustomerId = "CUST-9876"
    TotalAmount = 149.99
    CreatedAt  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.ffffffZ")
}

# 5. Convert the hashtable object to a JSON string
$JsonMessage = $OrderPayload | ConvertTo-Json -Compress

# 6. Encode the JSON string to Base64 (Required for Azure Storage Rest API compatibility)
$Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonMessage)
$Base64Message = [Convert]::ToBase64String($Bytes)

# 7. Add the message to the queue
try {
    $Queue.CloudQueue.AddMessageAsync([Microsoft.Azure.Storage.Queue.CloudQueueMessage]::new($Base64Message)) | Out-Null
    Write-Host "[Success] Order message sent to queue successfully!" -ForegroundColor Green
    Write-Host "Payload Sent: $JsonMessage" -ForegroundColor Gray
}
catch {
    Write-Error "Failed to send message: $_"
}
