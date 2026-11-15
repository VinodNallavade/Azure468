# Azure468

Hands-on examples and learning materials for Microsoft Azure. This repository brings together small application samples, Azure PowerShell labs, container demos, and reference material. The examples are independent; there is no single deployment pipeline or application that deploys the entire repository.

## Repository contents

| Path | Description |
| --- | --- |
| `azure-powershell/` | Standalone Az PowerShell examples for virtual machines, availability sets and zones, storage, web apps, application security groups, and networking. Networking labs cover public DNS, private endpoints, service endpoints, user-defined routes/NVAs, and regional/global VNet peering. |
| `azure-webapp/` | ASP.NET Core Minimal API targeting .NET 10. Includes a generated five-day weather forecast endpoint and OpenAPI/Swagger UI. |
| `azweb-envs/EnvironmentDemo/` | Small ASP.NET Core app demonstrating configuration through `APP_NAME`, `APP_ENV`, and `WELCOME_MESSAGE`. |
| `azure-container/` | FastAPI sample packaged in a Docker image. Provides `/` and `/health` endpoints. |
| `azure-storage/` | Static website sample and Azure Storage redundancy reference material. |
| `azure-policy/` | Azure Policy examples, PowerShell commands, and a compliance blueprint image. |
| `curriculum/` | Azure administrator/cloud engineer learning material. |
| `urls.txt` | A collection of related resource links. |

## Run the application samples locally

### ASP.NET Core weather API

Requires the .NET 10 SDK:

```powershell
cd azure-webapp
dotnet run
```

Use the URL printed by `dotnet run`; `/weatherforecast` returns sample forecast data and `/swagger` opens the API documentation.

### ASP.NET Core environment demo

Requires the .NET 10 SDK:

```powershell
cd azweb-envs/EnvironmentDemo
$env:APP_NAME = "Local demo"
$env:APP_ENV = "Development"
$env:WELCOME_MESSAGE = "Hello from my local environment"
dotnet run
```

The app also has defaults in `appsettings.json`. Environment variables can be used to override those settings.

### Python container sample

Requires Docker:

```powershell
docker build -t azure468-python-demo ./azure-container
docker run --rm -p 8000:8000 azure468-python-demo
```

Open `http://localhost:8000/` for the sample response or `http://localhost:8000/health` for the health response. To run without Docker, install `azure-container/requirements.txt` in a Python 3.11 environment and start Uvicorn with `uvicorn app:app --reload --app-dir azure-container --port 8000`.

### Static website

Open `azure-storage/staticwebsite/index.html` in a browser. The page uses the adjacent CSS and JavaScript files; its resume content is explicitly fictional sample content.

## Run Azure PowerShell labs

The scripts under `azure-powershell/` are individual demonstrations, not a single ordered installer. Review the script you intend to run and its comments first. Most Azure labs require an Azure subscription, permissions to create the demonstrated resources, and the Az PowerShell module:

```powershell
Install-Module Az -Scope CurrentUser
Connect-AzAccount
```

Some scripts sign in themselves. Check the subscription context, region, resource names, and network access settings before running. Labs that create VMs, public IPs, or paid App Service plans can incur Azure charges; use the documented cleanup steps when finished.

## Safety and configuration

These are educational examples, not production-ready deployment templates. Some scripts contain hard-coded demonstration credentials or permissive network settings. Replace credentials with secure interactive input or an appropriate secret store, restrict access to trusted sources, and never publish real secrets. Review every resource-creation or deletion command before execution.