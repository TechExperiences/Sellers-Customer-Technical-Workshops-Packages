# Prerequisites

This document lists everything needed to run the **Unify Data – Rapid Prototyping using GitHub Copilot** exercises on your **own local machine and tenant**.

## What the exercises build

| Step | Scenario | What gets created / used |
|------|----------|--------------------------|
| 1 | **Fabric workspace** | New workspace `Caldova-Pharma<ID>` attached to the existing Fabric capacity; the user gets **Admin** access |
| 2 | **Analytical + operational data into OneLake** | `Caldova-Lakehouse`; **shortcuts** to CSV files in Blob Storage; **Fabric Mirroring** of the Azure SQL `OperationalData` database, with shortcuts into the Lakehouse |
| 3 | **Business application data** | New **Fabric SQL Database** (`Caldova_BusinessApp_SQLDB`); an **Azure Logic App** loads files from Blob Storage into it |
| 4 | **Semantic model, report & Data Agent** | **Direct Lake** semantic model with relationships; Power BI report built with **Copilot in Power BI**; **Fabric Data Agent** |
| 5 | **Govern & secure** | **OneLake Catalog**: Explore, Govern and Secure tabs |
| 6 | **Microsoft 365 Copilot** | Data Agent published to **Microsoft 365 Copilot** (`Caldova_Pharma_DataAgent`) and tested there |

---

## 1. Licenses & Subscriptions

| License / Subscription | Required? | Why |
|------------------------|-----------|-----|
| **Active Azure subscription** | **Required** | Hosts the Storage account, Azure SQL, Fabric capacity and Logic App |
| **GitHub Copilot license** (Business / Enterprise) | **Required** | Copilot Chat in **Agent mode** builds the Fabric and Azure components. The org must allow the **Claude Sonnet 5** model (or another premium model) and have enough **premium requests**. |
| **Microsoft Fabric capacity (F SKU, paid)** | **Required** | Workspace, Lakehouse, Mirroring, Fabric SQL DB, Direct Lake. **Copilot in Power BI and Fabric Data Agents need a paid F2 or higher capacity.** Trial capacities don't support them. **F64** is recommended so viewers don't need Pro licenses. |
| **Power BI Pro** (or Premium Per User) | **Required** | Lets the user create and save the semantic model and report in a workspace (on capacities below F64). It's **included in Microsoft 365 E5**. |
| **Microsoft 365 Copilot** | **Required** (Step 6) | Lets the user open the published Data Agent in Microsoft 365 Copilot |
| **Microsoft 365 E5** (or E3 + Power BI Pro) | **Required as the base license** | Qualifying base license for Microsoft 365 Copilot. E5 also includes Power BI Pro and Purview governance features. |
| **Microsoft Entra ID work account** (same tenant as Azure and Fabric) | **Required** | The UPN used for workspace admin, SQL access and mirroring |

---

## 2. Applications (local machine)

- **Visual Studio Code** (latest) 
- **GitHub Copilot** + **GitHub Copilot Chat** extensions
- **Git**

---

## 3. Resources / Services Required

### Pre-provision these (the prompts reuse them)

Use the **exact names** below or update the prompts to match. `<ID>` = your suffix, for example the deployment ID.

| Resource | Name in guide | Configuration notes |
|----------|---------------|---------------------|
| **Resource group** | `rg-Unified` | Same region as the Fabric capacity is recommended |
| **Storage account** | `storage<ID>` | StorageV2. **Hierarchical namespace (ADLS Gen2) recommended** so OneLake shortcuts work. Public access, or the storage firewall must allow Fabric (trusted workspace access). |
| **Container** | `data` | Folder `Analytical/` holds the **CSV files** for the Lakehouse shortcuts (e.g. DimDate). Folder `BusinessApplication/` holds the **customer files** for the Logic App (CustomerDetails, CustomerAddress). |
| **Azure SQL logical server** | `sql-operational-<ID>` | **Microsoft Entra authentication** on, with your UPN as **Entra admin**. **System-assigned managed identity turned on** (required for Fabric Mirroring). Firewall: **Allow Azure services** plus your client IP. Keep the SQL admin password handy, because Copilot may ask for it. |
| **Azure SQL Database** | `OperationalData` | Filled with operational tables (e.g. `Inventory`). Tables need **primary keys** for mirroring. Use a vCore or DTU tier that supports mirroring. Serverless works, but auto-pause can delay mirroring. |
| **Fabric capacity** (Azure resource `Microsoft.Fabric/capacities`) | `fabriccapacity<ID>` | **F2 or higher, Running (not paused)**. Your UPN is listed as a **Capacity administrator**. |


### Data 

Before starting prototyping, you should have source data in our blob storage account which is created above to process.

Below are the different types of source data
 - Business Appplication Data:
    - *storage account :`storage<ID>`-> container :`data`-> folder: `Business Application`*-> Upload Documents
 - Analytical Data
    - *storage account :`storage<ID>`-> container :`data`-> folder: `Analytical`*-> Upload Documents
---

## 4. Roles / Permissions / API Permissions

### Azure RBAC

| Role | Assign to | Scope | Why it's needed |
|------|-----------|-------|-----------------|
| **Owner** *(or Contributor + User Access Administrator)* | User | Subscription or `rg-Unified` | Deploy the Logic App, API connections and integration resources; assign roles to managed identities |
| **Contributor** | Service Principal *(if used)* | Subscription or `rg-Unified` | Deploy resources without user interaction |
| **User Access Administrator (UAA)** | Service Principal *(if used)* | Subscription or `rg-Unified` | Grant the Logic App and Fabric identities access to Storage and SQL |
| **Storage Blob Data Owner** *(Storage Blob Data Contributor is the minimum)* | User / SP | Storage account (subscription works too) | Read CSV files for the shortcuts and give the Logic App access to the business application files. **Note:** Owner/Contributor alone does **not** give data access. |
| **Storage Blob Data Reader** | Logic App managed identity, plus Fabric workspace identity if used for the shortcut | Storage account | Lets the Logic App and shortcuts read the files |
| **Capacity administrator** | User (and SP if used) | Fabric capacity `fabriccapacity<ID>` | Assign the new workspace to the capacity |


### Fabric tenant settings (Fabric Admin portal → Tenant settings)

A **Fabric Administrator** must turn these on once, for the whole organization or a security group that includes the user. Setting names may vary slightly as Fabric changes.

1. **Data agent item types (preview)** enabled on the tenant.

2. Navigate to [Fabric](app.powerbi.com). Click on **Settings** and select **Admin portal**.

3. Enable **Data agent item types (preview)**.

    ![](../Sandbox-Environment-Guides/Images/pre-5.png)

### Microsoft 365 admin

- Microsoft 365 Copilot license assigned to the user
- Agents allowed in the **Microsoft 365 admin center → Integrated apps / Agents** policy, so the published Data Agent shows under **Agents → Your agents**

---

## 5. Values to Have Ready

-  Azure **subscription ID** and **tenant ID**
-  Your **UPN** (workspace admin, SQL connection)
- **SQL admin password** for `sql-operational-<ID>`.
- Names: `rg-Unified`, `storage<ID>`, container `data`, `fabriccapacity<ID>`, `sql-operational-<ID>`, `OperationalData`
- **GitHub username** with an active Copilot license, signed in to VS Code
---

## 6. Deploy `Unify-Package` locally

`Unify-Package` is the automated implementation of this scenario. It validates the bundled source files, provisions the Azure and Fabric foundation, loads the three source domains, and creates the governed Fabric analytics artifacts.

### Deployment steps

#### 1. Confirm the local tools and source folders

Use PowerShell 7 with Azure CLI (`az`), Azure Developer CLI (`azd`), Python 3, and `winget` available in the terminal. Keep the supplied `Analytical`, `Operational`, and `BusinessApplication` folders beside `up.ps1`; the pipeline validates and uploads their contents.

#### 2. Open the exact package folder

Open PowerShell 7. Set `$repoRoot` to the complete folder where **you** cloned `Sellers-Customer-Technical-Workshops` (for example, `C:\Repos\Sellers-Customer-Technical-Workshops`), then run:

```powershell
$repoRoot = "C:\path\to\Sellers-Customer-Technical-Workshops"
Set-Location (Join-Path $repoRoot "Build-a-unified-governed-data-and AI-estate\Unify-Package")
Get-Location
```

The displayed location must end with `Build-a-unified-governed-data-and AI-estate\Unify-Package`.

#### 3. Create and store the environment file

Create `.env` **inside this `Unify-Package` folder**, at the same level as `up.ps1`. Keep this local file private and do not commit it.

```powershell
Copy-Item .env.example .env
notepad .env
```

#### 4. Enter the `.env` values

Replace the placeholders in the opened `.env` file:

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

| `.env` entry | Enter this value |
|---|---|
| `AZURE_ENV_NAME` | A local Azure Developer CLI environment name, for example `unify-local`. |
| `AZURE_SUBSCRIPTION_ID` | The subscription GUID for the new Azure and Fabric resources. |
| `AZURE_TENANT_ID` | The Microsoft Entra tenant GUID for the deployment account. |
| `AZURE_LOCATION` | Keep `westus2`; it is used by the resource group and SQL deployment. |
| `AZURE_RESOURCE_GROUP` | Keep `rg-Build-Unify`; this is the resource group created by the package. |
| `FABRIC_CAPACITY_ADMIN_UPN` | The Fabric user principal name that becomes capacity and workspace administrator. |
| `SQL_ADMINISTRATOR_LOGIN` | SQL authentication administrator name. Keep `squnify` unless a different name is required. |
| `SQL_ADMINISTRATOR_PASSWORD` | Strong password for the new Azure SQL Server. |

#### 5. Save and run the complete deployment

Save and close Notepad. Return to the same PowerShell window, confirm it is still in the full `Unify-Package` path, then run:

```powershell
Set-Location (Join-Path $repoRoot "Build-a-unified-governed-data-and AI-estate\Unify-Package")
.\up.ps1
```

The command checks Azure CLI authentication, installs ODBC Driver 18 if necessary, imports `.env` into the selected Azure Developer CLI environment, validates the analytical, operational, and business-application source data, then runs `azd up --no-prompt`.

### What the pipeline creates

| Area | Created artifacts |
|---|---|
| Azure foundation | `rg-Build-Unify`; a Standard LRS Storage account in West US 3 with private `data` container; a timestamp-and-suffix Azure SQL Server and `OperationalData` database in West US 2; F16 Fabric capacity in West US 2. |
| Integration | `caldova-integration-account`, `caldova-businessapp-ingest` Logic App with system-assigned managed identity, and a managed-identity SQL API connection. The Logic App is granted Contributor access in the created Fabric workspace. |
| Source ingestion | Copies the 13 analytical CSVs, 8 operational CSVs, and 2 business-application JSON files to Blob Storage; loads operational data to Azure SQL; loads the customer JSON into the Fabric SQL Database; then copies the three domains into OneLake. Operational source blobs are removed after their Lakehouse copy. |
| Fabric workspace | `Caldova-Build-Unify-<stable-suffix>` on the newly created capacity, `Caldova_Lakehouse`, `Caldova_SQLDatabase`, and the Lakehouse ingestion notebook. |
| Governed analytics | Direct Lake semantic model `Caldova_Unified_SemanticModel`, report `Caldova_Unified_Report`, and published Data Agent `Caldova_Unified_DataAgent`. |

The Azure SQL server suffix changes on every run to avoid reusing a previous operational database. The Storage account, Fabric capacity, and workspace suffix are derived from the subscription and resource-group combination; they are stable for the same deployment target.

### Expected result

Successful output proceeds through validation, Azure provisioning, source upload, operational SQL load, Fabric workspace/Lakehouse setup, business-application ingestion, OneLake copy, semantic-model/report publication, and Data Agent publication. The final terminal output from `azd up` confirms that provisioning and post-provisioning completed.

### Verify after deployment

| Where | What to verify |
|---|---|
| Azure portal → Resource groups → `rg-Build-Unify` | Storage account, generated SQL Server, `OperationalData`, F16 Fabric capacity, Logic App, Integration Account, and SQL API connection. |
| Azure portal → Storage account → Containers → `data` | `Analytical/` and `BusinessApplication/` source folders. The `Operational/` folder is cleaned up after its content is copied to the Lakehouse. |
| Azure portal → SQL databases | `OperationalData` with the operational tables loaded. |
| [Microsoft Fabric](https://app.fabric.microsoft.com/) → Workspaces | `Caldova-Build-Unify-<stable-suffix>` with the Lakehouse, Fabric SQL Database, ingestion notebook, semantic model, report, and Data Agent. |
| Fabric Lakehouse | Delta tables in the **Tables** area for the unified data domains. |
| Fabric Data Agent | `Caldova_Unified_DataAgent` is published and uses `Caldova_Unified_SemanticModel` as its governed analytics source. |

---
