# Prerequisites

This document lists everything needed to run the **Rapid Prototyping using GitHub Copilot** exercises on your **own local/VM machine and Azure tenant**

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

If these resources are not already available, deploy the complete Azure modernization environment by following the [Miq-project-package deployment guide](Modernize_Package/README.md).

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
