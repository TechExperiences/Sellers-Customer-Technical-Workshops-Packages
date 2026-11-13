# Prerequisites

This document lists everything needed to run the **Rapid Prototyping using GitHub Copilot** exercises on your **own local machine and Azure tenant**

The exercises cover three scenarios:

| # | Scenario | What GitHub Copilot does | Approx. time |
|---|----------|--------------------------|--------------|
| 1 | **SQL Server → Azure SQL Database Hyperscale** | Uses the architecture diagram and `Caldova_DB_script` to create tables, load data and keep relationships in the `CaldovaOrderManagement` Hyperscale database, and sets your UPN as the Entra admin | 10–20 min |
| 2 | **Web app → Azure App Service (.NET 10)** | Migrates the `CaldovaOrderManagement` MVC app to App Service, modernizes the UI, connects it to Azure SQL and adds a *Traditional SQL Search* page | 20–30 min |
| 3 | **Vector / semantic search** | Runs `Embedding_Script.sql`, generates Azure OpenAI embeddings into a `VECTOR` column (`dbo.ProductDescriptionEmbeddings`) and adds a *Semantic Vector Search* page with charts | 15–30 min |

---
**Source Environment**
- **Option 1:** If you already have an **on-premises SQL** Server and **web application**, you can directly proceed to the Prototype section and follow the instructions provided there.
- **Option 2:** If you do not have above, you can use the provided **source Artifacts** to create and configure them manually before proceeding with the Prototype instructions



---

## 1. Licenses & Subscriptions

| Item | Required? | Why |
|------|-----------|-----|
| **Azure subscription** (Pay-As-You-Go, EA, CSP or MCAPS) | **Required** | Hosts Azure SQL Hyperscale, App Service and Azure OpenAI. Must be able to create billable resources. |
| **GitHub Copilot license** (Business or Enterprise; Pro/Pro+ also works for individuals) | **Required** | Copilot Chat in **Agent mode** builds and deploys everything. |
| **GitHub account** with access to **Claude Sonnet 5** (or another premium model) | **Required** | The guide selects *Claude Sonnet 5*. The GitHub org admin must turn on that model in the Copilot policy. You also need enough **premium requests**, because agent sessions use many. |
| **Microsoft Entra ID work account** (in the same tenant as the subscription) | **Required** | Set as the **Microsoft Entra admin** on the SQL server, and used for Query Editor sign-in and Azure CLI device-code login. |
| **Microsoft 365 E5** | Optional | Not needed by these exercises. Any Entra ID user works. Keep it only if other modules in the series need it. |
| **Azure OpenAI access** (Azure AI Foundry) | **Required** | Generates the embeddings for semantic search. |

---

## 2. Identity – User vs Service Principal

The guide runs as an **interactive user**. Copilot signs in through the Azure CLI **device-code login**, and you confirm it with *"Yes, completed → Submit"*. You **don't need a service principal** for the core exercises.

A service principal is **recommended (optional)** if you want to:
- Run the deployment without user interaction or reuse it in CI/CD (GitHub Actions)
- Keep deployment rights separate from a personal account

If you use one, it needs the same Azure RBAC roles as the user (section 3) plus the Graph permissions in section 4.

---

## 3. Azure Roles / RBAC

**Scope:** apply these at the **subscription** level or, at minimum, on the created resource group (e.g.**`rg-caldova-modernize`**.)

| Role | Assign to | Scope | Why it's needed |
|------|-----------|-------|-----------------|
| **Owner** *(or Contributor + User Access Administrator)* | User / Service Principal | Subscription or Resource Group | Deploy Bicep/ARM templates and create the App Service plan and Web App. Also lets Copilot assign roles to the Web App managed identity. |
| **User Access Administrator (UAA)** | Service Principal (if used) | Subscription or RG | Lets the SP create role assignments, for example Web App identity → Azure OpenAI or SQL. Not needed if the SP already has Owner. |
| **SQL Server Contributor** *(included in Owner)* | User / SP | SQL server | Set the Entra admin, change firewall rules and scale Hyperscale. |
| **Microsoft Entra admin on the Azure SQL logical server** | User (your UPN) | SQL server | The prompt says *"Make UPN … admin to the Azure SQL server and hyperscale database"*. Needed to create Entra users and to sign in with the Query Editor. |
| **Cognitive Services OpenAI User** | User and Web App managed identity | Azure OpenAI resource | Call the embedding model (app and SQL script). |
| **Cognitive Services Contributor** *(or Azure AI / Foundry Owner)* | User | Azure OpenAI resource | Read the endpoint and **keys** for `.env` and create or check model deployments. |
| **Website Contributor** *(included in Owner)* | User / SP | RG | Deploy code to App Service and update app settings. |

---

## 4. Azure Resources to Pre-Provision

The prompts tell Copilot to **reuse existing resources**, so create these **before** the session. Use the **exact names** below or update the prompts to match.

| Resource | Name / setting | Notes |
|----------|----------------|-------|
| Resource group | `rg-caldova-modernize` | Use a region that offers SQL Hyperscale, App Service (.NET 10) and Azure OpenAI. |
| Azure SQL logical server | e.g. `sql-caldova-<id>` | **Microsoft Entra authentication** enabled. Keep the SQL admin password handy, because Copilot may ask for it. Enable a **system-assigned managed identity** (needed for section 4). |
| Azure SQL Database (**Hyperscale** tier) | `CaldovaOrderManagement` | Start with an empty database. Needs the native **`VECTOR`** data type, which Azure SQL Database supports. |
| SQL server firewall | Allow **your client IP** and **Allow Azure services** | Lets your laptop run scripts and lets App Service connect. |
| Azure OpenAI / Foundry resource | e.g. `aoai-caldova-<id>` | Its **endpoint** and **API key** go into `.env`. |
| Embedding model deployment | e.g. `text-embedding-3-small` (1536 dims) or `text-embedding-ada-002` | Needs enough **TPM quota** in your region. The vector dimension must match the model. |
| App Service plan + Web App | Created by Copilot (`app-caldova-<id>`) | You need **App Service quota** (Basic B1 or higher) in the region. |

---

## 5. Local Machine – Software

- **Visual Studio Code** (latest) 
- **GitHub Copilot** + **GitHub Copilot Chat** extensions
- **Git**
---

## 6. Values to Have Ready Before Starting

- Azure **subscription ID** and **tenant ID**
- Your **Entra UPN** (to set as SQL Entra admin)
- **SQL admin login / password** for the logical server
- **Azure OpenAI endpoint**, **API key** and **embedding deployment name**
- **GitHub username** signed in to VS Code with an active Copilot license
---

## 7. Deploy `Miq-project-package` locally

`Miq-project-package` is the automated Azure deployment path for the Caldova modernization demo. It uses the local CSV files in its `data` folder to build the application data estate.

The pipeline provisions Azure infrastructure, imports the supplied relational data, generates vector embeddings, configures managed-identity access, deploys the ASP.NET Core web application, and validates the live semantic-search route.

### Deployment steps

#### 1. Confirm the local tools and source data

Use PowerShell 7 with Azure CLI (`az`), Azure Developer CLI (`azd`), .NET 10 SDK, and Git available in the terminal. Keep the supplied CSV files in `Miq-project-package\data`; the pipeline imports eleven source tables and generates the embeddings table itself.

#### 2. Open the exact package folder

Open PowerShell 7. Set `$repoRoot` to the complete folder where **you** cloned `Sellers-Customer-Technical-Workshops` (for example, `C:\Repos\Sellers-Customer-Technical-Workshops`), then run:

```powershell
$repoRoot = "C:\path\to\Sellers-Customer-Technical-Workshops"
Set-Location (Join-Path $repoRoot "Modernize-with-confidence\Miq-project-package")
Get-Location
```

The displayed location must end with `Modernize-with-confidence\Miq-project-package`.

#### 3. Create and store the environment file

Create `.env` **inside this `Miq-project-package` folder**, at the same level as `up.ps1`. Keep this file on the deployment machine and do not commit it.

```powershell
Copy-Item .env.example .env
notepad .env
```

#### 4. Enter the required `.env` values

Replace these four placeholders in the opened `.env` file:

```dotenv
AZURE_SUBSCRIPTION_ID=<SUBSCRIPTION_GUID>
SQL_ADMINISTRATOR_PASSWORD=<STRONG_SQL_ADMIN_PASSWORD>
SQL_ENTRA_ADMIN_LOGIN=<MICROSOFT_ENTRA_ADMIN_UPN>
SQL_ENTRA_ADMIN_OBJECT_ID=<MICROSOFT_ENTRA_ADMIN_OBJECT_ID>
```

| `.env` entry | Enter this value |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | The target Azure subscription GUID. |
| `SQL_ADMINISTRATOR_PASSWORD` | A strong password for the newly created SQL logical server. |
| `SQL_ENTRA_ADMIN_LOGIN` | The Microsoft Entra administrator UPN for the new SQL server. |
| `SQL_ENTRA_ADMIN_OBJECT_ID` | The Entra object ID for the same SQL administrator user. |

#### 5. Review the optional `.env` values

These values may be retained as shown in `.env.example`, or changed when your deployment requires them:

```dotenv
AZURE_ENV_NAME=Miq-project-package
SQL_ADMINISTRATOR_LOGIN=sqladmincaldova
SQL_MIGRATION_CLIENT_IP=<OPTIONAL_PUBLIC_IP>

# Set all three only when non-interactive service-principal sign-in is required.
AZURE_CLIENT_ID=<SERVICE_PRINCIPAL_CLIENT_ID>
AZURE_TENANT_ID=<TENANT_ID>
AZURE_CLIENT_SECRET=<SERVICE_PRINCIPAL_CLIENT_SECRET>
```

| `.env` entry | How it is used |
|---|---|
| `AZURE_ENV_NAME` | Local Azure Developer CLI environment name. `Miq-project-package` is the default. |
| `SQL_ADMINISTRATOR_LOGIN` | SQL authentication administrator login. `sqladmincaldova` is the default. |
| `SQL_MIGRATION_CLIENT_IP` | Optional public IP used while loading the initial data. When left blank, the pipeline detects the current public IP. |
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_SECRET` | Set all three together only when deployment signs in using a service principal. Leave all three unset for interactive sign-in. |
| `AZURE_OPENAI_*` values already in `.env.example` | Package defaults for the app model names and API versions. The pipeline creates the OpenAI account and writes the deployed endpoint to the application configuration. |

#### 6. Save and run the complete deployment

Save and close Notepad. Return to the same PowerShell window, confirm it is still in the full `Miq-project-package` path, then run:

```powershell
Set-Location (Join-Path $repoRoot "Modernize-with-confidence\Miq-project-package")
.\up.ps1
```

The command creates or selects the local azd environment, stores the subscription context, then runs `azd up --no-prompt`. Its hooks run the full six-stage migration and application deployment.

### What the pipeline creates

| Resource / result | Name or configuration |
|-------------------|-----------------------|
| Resource group | `rg-MWC`; reused if it already exists |
| App Service plan | `plan-caldova-ordermgmt`, Basic B1 by default |
| ASP.NET Core web app | `app-caldova-ordermgmt-<8-character-suffix>` |
| Azure SQL logical server | `sql-caldova-<8-character-suffix>` |
| Azure SQL Hyperscale database | `CaldovaOrderManagement`, `HS_Gen5_2` by default |
| Azure OpenAI account | `openai-caldova-<8-character-suffix>` in West US |
| Azure OpenAI deployments | `gpt-5-mini` and `text-embedding-ada-002` |
| Relational migration | Eleven source CSV tables imported into `dbo` |
| AI modernization result | `dbo.ProductDescriptionEmbeddings` with native `VECTOR(1536)` embeddings |
| App security | System-assigned managed identity, database `db_datareader` / `db_datawriter` membership, Cognitive Services OpenAI User role, and SQL firewall rules for App Service outbound IPs |

Location behavior is intentional:

- The resource group starts in West US 2 when possible.
- App Service and SQL independently fall back across supported US regions if needed.
- Azure OpenAI and both model deployments are fixed to **West US**; the deployment stops rather than placing models in a different region.

Each run generates a new suffix for the web app, SQL server, and Azure OpenAI account. Earlier failed resources are not reused or automatically deleted; remove them manually when no longer needed to avoid charges.

### Expected completion output

A successful run includes output similar to the following:

```text
[MIQ 1/6] Provisioning resource group, App Service, Azure SQL, and Azure OpenAI...
[MIQ 3/6] Creating schema and importing the 11 simulated on-prem CSV exports...
Pipeline verification succeeded: 11 source tables imported and <n> generated embeddings stored in dbo.ProductDescriptionEmbeddings.
[MIQ 5/6] Configuring App Service identity, SQL access, OpenAI access, and network rules...
[MIQ 6/6] Building and deploying the Caldova web UI...
Semantic-search validation passed: Azure OpenAI embedding, Azure SQL vector ranking, and dashboard logging are working.
Web UI deployed: https://app-caldova-ordermgmt-<suffix>.azurewebsites.net
```

The pipeline removes the temporary migration-client SQL firewall rule when it finishes. It keeps the App Service outbound-IP firewall rules because the live web app uses Azure SQL over public endpoints; there is no VNet in this demo configuration.

### Where to verify the deployment

- **Azure portal**: Open **Resource groups** → `rg-MWC`. The group contains the App Service plan/web app, SQL server/database, and Azure OpenAI account.
- **Web application**: Open the generated `https://app-caldova-ordermgmt-<suffix>.azurewebsites.net` URL shown in the terminal. Use the **Semantic Search** page to verify Azure OpenAI embeddings and Azure SQL vector ranking.
- **Azure SQL Database**: Open `CaldovaOrderManagement` under the generated `sql-caldova-<suffix>` server. In Query Editor or another Entra-authenticated SQL client, verify the imported tables and `dbo.ProductDescriptionEmbeddings`.
- **Azure OpenAI / Foundry**: Open the generated `openai-caldova-<suffix>` resource in Azure portal or Microsoft Foundry. **Model deployments** shows `gpt-5-mini` and `text-embedding-ada-002`.
- **App Service**: Open the generated web app → **Identity** to verify its system-assigned identity, and **Configuration** to review the generated application settings.

---
