# Unify-Package deployment guide

`Unify-Package` validates the bundled source files, provisions the Azure foundation and F16 Fabric capacity, retains analytical and business-application source data in Azure Storage, and loads the operational source domain into Azure SQL before removing its temporary Blob landing files.

## Run from the VS Code integrated terminal

1. Start **Visual Studio Code** and select **Terminal** → **New Terminal**.

![New Terminal](images/image8.png)

2. In the VS Code terminal, choose a parent folder for the repository, clone it once, and open the clone in VS Code:

```powershell
New-Item -ItemType Directory -Path "C:\Repos" -Force | Out-Null
Set-Location "C:\Repos"
git clone https://github.com/TechExperiences/Sellers-Customer-Technical-Workshops-Packages.git
Set-Location ".\Sellers-Customer-Technical-Workshops-Packages"
code .
```

![Clone repo](images/image0.png)

3. In the VS Code window opened for the clone, select **Terminal** → **New Terminal** again. Move to this package folder, create `.env` if it does not exist, and open it for editing:

```powershell
Set-Location ".\Build-a-unified-governed-data-and AI-estate\Unify-Package"
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
code .env
```

![Unify-Package .env](images/image1.png)

4. Enter the required `.env` values, save the file, return to the same terminal, and run the one deployment command:

```powershell
.\up.ps1
```

## 1. Confirm the local tools and source folders

Use PowerShell 7 with Azure CLI (`az`), Azure Developer CLI (`azd`), Python 3, and `winget` available in the terminal. Keep the supplied `Analytical`, `Operational`, and `BusinessApplication` folders beside `up.ps1`; the pipeline validates all three, retains Analytical and BusinessApplication files in Blob Storage, then removes the temporary Operational Blob files after their Azure SQL load succeeds.

## Deployment regions

| Resource or workload | Region |
|---|---|
| Resource group `rg-Build-Unify` | **West US 2** (`westus2`). |
| Azure SQL Server and `OperationalData` database | **West US 2**. |
| F16 Fabric capacity | **West US 2**. |
| Storage account and private `data` container | **West US 3** (`westus3`). |

## Enable Azure resource providers

In Azure portal, open **Subscriptions** → select the deployment subscription → **Resource providers**. Register these namespaces if their status is not **Registered**:

- `Microsoft.Fabric`
- `Microsoft.Storage`
- `Microsoft.Sql`

Or run:

```powershell
az provider register --namespace Microsoft.Fabric --wait
az provider register --namespace Microsoft.Storage --wait
az provider register --namespace Microsoft.Sql --wait
```

## 2. Open this deployment folder

Set `$repoRoot` to the folder where you cloned `Sellers-Customer-Technical-Workshops-Packages`, then run:

```powershell
$repoRoot = "C:\path\to\Sellers-Customer-Technical-Workshops-Packages"
Set-Location (Join-Path $repoRoot "Build-a-unified-governed-data-and AI-estate\Unify-Package")
Get-Location
```

## 3. Create and edit `.env`

Create `.env` in this `Unify-Package` folder, beside `up.ps1`. Keep this local file private and do not commit it.

```powershell
Copy-Item .env.example .env
notepad .env
```

Replace the placeholders:

```dotenv
AZURE_ENV_NAME=unify-local
AZURE_SUBSCRIPTION_ID=<YOUR_SUBSCRIPTION_ID>
AZURE_TENANT_ID=<YOUR_TENANT_ID>
AZURE_LOCATION=westus2
AZURE_RESOURCE_GROUP=rg-Build-Unify
FABRIC_CAPACITY_ADMIN_UPN=<YOUR_USER_PRINCIPAL_NAME>
SQL_ADMINISTRATOR_LOGIN=squnify
SQL_ADMINISTRATOR_PASSWORD=<STRONG_SQL_PASSWORD>
```

| Entry | Value |
|---|---|
| `AZURE_ENV_NAME` | Local Azure Developer CLI environment name, for example `unify-local`. |
| `AZURE_SUBSCRIPTION_ID` | Subscription GUID for the new Azure and Fabric resources. |
| `AZURE_TENANT_ID` | Microsoft Entra tenant GUID for the deployment account. |
| `AZURE_LOCATION` | Keep `westus2`. |
| `AZURE_RESOURCE_GROUP` | Keep `rg-Build-Unify`. |
| `FABRIC_CAPACITY_ADMIN_UPN` | Fabric user principal name that becomes the capacity administrator. |
| `SQL_ADMINISTRATOR_LOGIN` | SQL authentication administrator name. |
| `SQL_ADMINISTRATOR_PASSWORD` | Strong password for the new Azure SQL Server. |

## 4. Run the complete deployment

Save `.env`, remain in this folder, then run:

```powershell
Set-Location (Join-Path $repoRoot "Build-a-unified-governed-data-and AI-estate\Unify-Package")
.\up.ps1
```

The command checks Azure CLI authentication, installs ODBC Driver 18 when necessary, imports `.env` into the selected Azure Developer CLI environment, validates the source data, and runs `azd up --no-prompt`.

Before provisioning, the pipeline identifies the Azure CLI deployment identity and saves its object ID and type into the local azd environment. Bicep then assigns that identity **Storage Blob Data Contributor** on the new storage account. No Blob role values are required in `.env`; the upload stage waits for the new assignment to propagate.

## What is created

| Area | Created artifacts |
|---|---|
| Azure foundation | `rg-Build-Unify`; Storage account with private `data` container; a new Azure SQL Server and `OperationalData` database; F16 Fabric capacity. |
| Fabric | F16 Fabric capacity only. No Fabric workspace, Lakehouse, Fabric SQL Database, notebook, semantic model, report, or Data Agent is created. |

## Verify the result

- **Azure portal** → **Resource groups** → `rg-Build-Unify` for Storage, generated SQL Server, and Fabric capacity.

  ![rg-Build-Unify](images/image2.png)

  ![data container](images/image4.png)

  ![Analytical files](images/image5.png)

  ![BusinessApplication files](images/image6.png)

  After the deployment succeeds, the `data` container contains only `Analytical/` and `BusinessApplication/`. `Operational/` is deleted after the Azure SQL load completes.

- **Azure portal** → select the generated Azure SQL Server → **Databases** → `OperationalData` to confirm the operational tables were loaded.

- **Microsoft Fabric** → **Capacity settings** to confirm the F16 Fabric capacity. This package intentionally creates no workspace or workspace items.
