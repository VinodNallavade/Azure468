
# ============================================================
# Azure Web App - End-to-End Demonstration
# Creates: Resource Group, App Service Plan, Web App
# Deploys: Custom HTML application
# ============================================================


# ---------- 1. Configuration ----------
$Location       = "East Us"
$ResourceGroup  = "rg-webapp-eastus-demo"
$PlanName       = "asp-webapp-eastus-demo"
$AppName        = "azweb-webdemo-eastus$(Get-Random -Minimum 10000 -Maximum 99999)"
$PlanSku        = "B1"  # Basic tier - billable

$WorkFolder = Join-Path $env:TEMP "AzureWebAppDemo"
$SiteFolder = Join-Path $WorkFolder "site"
$ZipPath    = Join-Path $WorkFolder "site.zip"

Write-Host "`n=== Azure Web App Demo ===" -ForegroundColor Cyan
Write-Host "App Name: $AppName"
Write-Host "Region:   $Location"

# ---------- 2. Install and import Az modules ----------
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Install-Module Az -Scope CurrentUser -Repository PSGallery -Force
}

Import-Module Az.Accounts
Import-Module Az.Resources
Import-Module Az.Websites

# ---------- 3. Sign in to Azure ----------
Connect-AzAccount -Tenant "91f820e7-a557-448d-8ccf-c7452516ce24"

Get-AzSubscription |
    Select-Object Name, Id, State |
    Format-Table -AutoSize

$SubscriptionId = Read-Host "Enter the subscription ID to use"
Set-AzContext -SubscriptionId $SubscriptionId

# ---------- 4. Create resource group ----------
New-AzResourceGroup `
    -Name $ResourceGroup `
    -Location $Location `
    -Tag @{ Purpose = "WebAppDemo"; Owner = "Training" }

# ---------- 5. Create App Service Plan ----------
# Windows hosting; B1 is a paid tier.
New-AzAppServicePlan `
    -Name $PlanName `
    -ResourceGroupName $ResourceGroup `
    -Location $Location `
    -Tier "Basic" `
    -NumberofWorkers 1 `
    -WorkerSize "Small"

# ---------- 6. Create Web App ----------
New-AzWebApp `
    -Name $AppName `
    -ResourceGroupName $ResourceGroup `
    -Location $Location `
    -AppServicePlan $PlanName `
    -Tag @{ Purpose = "WebAppDemo" } -

# Enforce HTTPS for incoming requests.
Set-AzWebApp `
    -Name $AppName `
    -ResourceGroupName $ResourceGroup `
    -HttpsOnly $true

# ---------- 7. Create the website ----------
New-Item -ItemType Directory -Path $SiteFolder -Force |
    Out-Null

$Html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Azure Web App Demo</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      background: #f2f5fb;
      margin: 0;
      padding: 50px 20px;
      color: #172554;
    }
    main {
      max-width: 700px;
      margin: auto;
      background: white;
      padding: 35px;
      border-radius: 16px;
      box-shadow: 0 8px 30px #0001;
    }
    h1 { color: #2563eb; }
    .tag {
      display: inline-block;
      padding: 8px 12px;
      background: #dbeafe;
      border-radius: 8px;
    }
  </style>
</head>
<body>
  <main>
    <span class="tag">Hosted on Microsoft Azure</span>
    <h1>My first Azure Web App!</h1>
    <p>This application is running on Azure App Service.</p>
    <h3>Demo details</h3>
    <p><b>Application:</b> $AppName</p>
    <p><b>Hosting:</b> Azure App Service</p>
    <p><b>Deployment:</b> PowerShell ZIP deployment</p>
    <p>Update the HTML and redeploy to demonstrate a release.</p>
  </main>
</body>
</html>
"@

Set-Content -Path (Join-Path $SiteFolder "index.html") `
    -Value $Html -Encoding utf8

# ---------- 8. Package the website ----------
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

Compress-Archive `
    -Path (Join-Path $SiteFolder "*") `
    -DestinationPath $ZipPath `
    -Force

# ---------- 9. Deploy the website ----------
Publish-AzWebApp `
    -ResourceGroupName $ResourceGroup `
    -Name $AppName `
    -ArchivePath $ZipPath `
    -Force `
    -Timeout 300000

# ---------- 10. Configure an application setting ----------
$AppSettings = @{
    DEMO_ENVIRONMENT = "Azure"
    DEMO_VERSION     = "1.0"
}

Set-AzWebApp `
    -ResourceGroupName $ResourceGroup `
    -Name $AppName `
    -AppSettings $AppSettings

# ---------- 11. Display results ----------
$WebApp = Get-AzWebApp `
    -ResourceGroupName $ResourceGroup `
    -Name $AppName

$Url = "https://$($WebApp.DefaultHostName)"

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host "Resource Group : $ResourceGroup"
Write-Host "App Service Plan: $PlanName"
Write-Host "Web App        : $AppName"
Write-Host "URL            : $Url" -ForegroundColor Cyan

Write-Host "`nOpening website..."
Start-Process $Url

Write-Host "`nKeep the resource group name to clean up after the demo."



#Remove-AzResourceGroup -Name $ResourceGroup -Force
