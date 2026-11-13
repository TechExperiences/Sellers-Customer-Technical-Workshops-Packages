# Prerequisites

This document lists everything needed to run the **Ubiquitous Innovation – Rapid Prototyping** exercises on your **own local/vm machine and Azure tenant.**

## What the exercises cover

| Topic | Activities | Built / used with |
|-------|------------|-------------------|
| **1 – Build agents and software at the speed of AI** | Clone repo → `Design-Review.md` in **Plan** mode → push to `main` → pick a model (`/model`, `/model auto`) in the **GitHub Copilot app** → `/delegate` to the **coding agent** → draft PR → **Copilot code review** → `@copilot` fixes → merge | VS Code + GitHub Copilot Chat, **GitHub Copilot app**, GitHub repo |
| **2 – Agents that know your business** | Check the existing `supply-chain-bi-agent` → change the model to **GPT-5.4** → add the **Fabric Data Agent** (Fabric IQ tool) → **Foundry IQ** knowledge base from Blob (AI Search + `text-embedding-3-small`) → **SharePoint (Work IQ)** tool → **Evaluation** | Microsoft Foundry, Fabric, Azure AI Search, SharePoint |
| **3 – From one agent to a coordinated system** | New **Developer environment with Dataverse** → **Copilot Studio** agent built with the *GitHub Copilot* option ("Market Launch Coordinator") → connect the Foundry agent → **Skill** → publish to **Teams + Microsoft 365** → **Workflow** triggered by Outlook *When a new email arrives* | Power Platform admin center, Copilot Studio, Teams, Outlook |
| **4 – Trust and cost are the same conversation** | **Agent 365** (All agents, agent map, Details, Data & tools, Activity, Permissions and Security tabs) → Entra / Purview / Foundry guardrails / Defender review → **Purview** Compliance Manager, Data Security Investigations, DLP analytics → **M365 admin center Billing** | Microsoft 365 admin center, Entra, Purview, Defender |

---

## 1. Licenses

| License | Required? | Why |
|---------|-----------|-----|
| **Active Azure subscription** | **Required** | Foundry, AI Search, Storage, Fabric capacity. It must allow **GPT-5.4** and **text-embedding-3-small** deployments (check region availability and quota). |
| **GitHub Copilot license** – **Business or Enterprise** (Pro+ for individuals) | **Required** | Agent and Plan mode, the **Copilot coding agent** (`/delegate`), **Copilot code review** and `@copilot` PR comments. The org policy must turn on the **coding agent** and the premium models (**Claude Sonnet 5**, Auto/Fusion). |
| **Microsoft 365 E5** (with Teams) | **Required** | Exchange (email trigger), SharePoint, Teams, **Purview** (Compliance Manager, DLP, DSPM for AI) and **Defender for Cloud Apps** |
| **Microsoft 365 Copilot** | **Required** | The Foundry **SharePoint (Work IQ)** tool needs a Microsoft 365 Copilot license for the signed-in user. It also gives Work IQ context in Copilot Studio and access to the agent in Microsoft 365 Copilot. |
| **Microsoft Copilot Studio** user license + **Copilot Studio capacity / Copilot Credits** (or pay-as-you-go on the environment) | **Required** | Build, publish and run the Market Launch Coordinator, its skill and the workflow |
| **Microsoft Agent 365** | **Required** (Topic 4) | **Agents** in the Microsoft 365 admin center: inventory, agent map, Entra agent ID, activity and security tabs. Your tenant may need **Frontier / early access** turned on. |
| **Microsoft Fabric capacity** (paid **F SKU**, F2+; F16+ recommended) | **Required** | Hosts the Fabric Data Agent used as a Foundry tool. **The trial capacity isn't supported for Data Agents.** |
| **Workspace Admin/Member** on the Fabric workspace + **access to the published Data Agent** | User (and everyone testing in Foundry, Copilot Studio or Teams) | The Fabric IQ tool runs **as the signed-in user** |
| **Read (Member/Visitor)** on the `EnterpriseAIKnowledgeBase` site | Same users | The SharePoint (Work IQ) tool honours the user's SharePoint permissions |
| **Power Platform Administrator** | User | Create the **Developer environment with Dataverse** in the Power Platform admin center. Alternatively, the tenant setting must let users create developer environments. |

---

## 2. Applications (local machine)

- **Visual Studio Code** (latest) 
- **GitHub Copilot** + **GitHub Copilot Chat** extensions
- **Git**

---

## 3. Resources / Services Required

| Resource | Name in guide | Configuration notes |
|----------|---------------|---------------------|
| **GitHub organization + repository** | `CL-Labs-04/UI-<ID>` → your own, e.g. `<your-org>/UI-Caldova` | Holds the **existing agent project scaffold**, the **"make the agent act"** issue and `Future-State-Architecture.png`. You need **Admin / Maintain** rights. **Copilot coding agent** and **Copilot code review** turned on for the repo. Branch protection can't block the merge, or you must be able to approve it. |
| **Resource group** | `rg-ubiquitous` | Choose a region where GPT-5.4 is available |
| **Microsoft Foundry resource + project** | `ubiquitous-innovation-project` | Project managed identity turned on |
| **Model deployments** | **GPT-5.4**, **text-embedding-3-small** | Enough TPM quota. GPT-5.4 is also used as the evaluation judge. |
| **Storage account (ADLS Gen2)** | name starts with `adlsubiquitous` | Container **`data`** with the **5 Caldova manufacturing documents** (scheduling guidance, procedures) |
| **Azure AI Search** | *(existing or created by Copilot)* | **Basic or higher** (semantic ranker/agentic retrieval); system-assigned managed identity turned on |
| **Fabric capacity + workspace** | `Ubiquitous-Innovation-<suffix>` | Lakehouse with manufacturing data (e.g. **PL01** November capacity utilization) |
| **Fabric Data Agent** (published) | `Ubiquitous_Innovation_DataAgent` | Must be **published** before Foundry can add it through *Fabric IQ (OneLake Catalog)* |
| **SharePoint site** | `EnterpriseAIKnowledgeBase` → Shared Documents/**AI Knowledge Base** | `Caldova_Business_Roles_and_Responsibilities.docx`, `Caldova_Launch_Business_Context.docx`, `Caldova_Launch_Commitments_and_Decisions.docx`. **Replace the lab tenant URL** (`sandboxailabs1002`) with your own site. |
---
#### Base Foundry Agent + GitHub Code Repo

- You should have an existing Microsoft Foundry agent and its source code available in a GitHub repository to enhance. 
- If you do not have an existing agent, you can use the provided prebuilt source code([TBD Link](https://hithub.com)) to deploy the agent and proceed with the subsequent steps.

## 4. Roles / Permissions / API Permissions

### Azure RBAC

| Role | Assign to | Scope | Why it's needed |
|------|-----------|-------|-----------------|
| **Owner** *(or Contributor + UAA)* | User | Subscription or `rg-ubiquitous` | Change Foundry, AI Search and Storage, and create role assignments for managed identities |
| **Contributor** | Service Principal | Subscription or `rg-ubiquitous` | Unattended provisioning |
| **User Access Administrator (UAA)** | Service Principal | Subscription or `rg-ubiquitous` | Grant Search ↔ Storage ↔ Foundry identity roles |
| **Storage Blob Data Owner** *(Storage Blob Data Contributor is the minimum)* | User / SP | Subscription or storage account | Read and upload the 5 documents. Owner alone gives **no data access**. |
| **Foundry Owner** (**Azure AI Owner**) *(or Azure AI Account Owner + **Azure AI User**)* | User / SP | Subscription or Foundry resource | Edit the agent (model, tools, knowledge), run the playground and **Evaluations** |
| **Search Service Contributor + Search Index Data Contributor** | User / SP | AI Search | Create the index, indexer and knowledge base |
| **Storage Blob Data Reader** | AI Search managed identity | Storage account | Blob ingestion |
| **Cognitive Services OpenAI User** | AI Search managed identity | Foundry resource | Vectorize with `text-embedding-3-small` |
| **Search Index Data Reader** | Foundry project managed identity | AI Search | Let the agent query the knowledge base |
| **Capacity administrator** | User (+ SP) | Fabric capacity | Workspace assignment |

### API permissions (Service Principal – admin consent required)

| Permission | API / Type | Why |
|------------|-----------|-----|
| **User.Read.All** | Microsoft Graph · Application | Look up user object IDs for role, workspace and site assignments |
| **GroupMember.ReadWrite.All** | Microsoft Graph · Application | Add users to the **security groups** that receive licenses (Copilot, Copilot Studio, Agent 365) and the Fabric tenant-setting scopes. Setup automation only. |
| **DataAgent.Execute.All** | **Power BI Service** | Lets the SP **call the Fabric Data Agent** programmatically, for example to validate or test the agent during setup. The Foundry and Copilot Studio steps themselves use the **user's** identity. Also needs the *Service principals can use Fabric APIs* tenant setting. |

### Tenant settings to turn on once

**Fabric Admin portal**

A **Fabric Administrator** must turn these on once, for the whole organization or a security group that includes the user. Setting names may vary slightly as Fabric changes.

1. **Data agent item types (preview)** enabled on the tenant.

2. Navigate to [Fabric](app.powerbi.com). Click on **Settings** and select **Admin portal**.

3. Enable **Data agent item types (preview)**.

    ![](../Sandbox-Environment-Guides/Images/pre-5.png)

**GitHub organization (Copilot policies)**
- Copilot **coding agent** turned on for the repo
- **Copilot code review** turned on
- Premium models (**Claude Sonnet 5**, Auto/Fusion) allowed
- Copilot **Plan** mode / agent mode allowed in the IDE
---

## 6. Values to Have Ready

- Azure **subscription ID** and **tenant ID**; your **UPN**
- **GitHub repo URL**, plus a Git username and email for commit authoring
- **Foundry project endpoint** (project overview) for the Copilot Studio connection
- Foundry **agent ID**: `supply-chain-bi-agent`
- Fabric workspace name and Data Agent name
- **SharePoint site URL** of your `EnterpriseAIKnowledgeBase` library

---

## 7. Deploy Fabric Automation locally

The `FabricAutomation` folder provisions the Ubiquitous Innovation Fabric, Azure data, and Foundry foundation in one creation-only pipeline. It signs in to Azure with the service-principal values stored in `.env`.

### Deployment steps

#### 1. Confirm the local tools and source folders

Use PowerShell 7 with Azure CLI (`az`) and Python 3 available in the terminal. Keep the supplied source folders beside `up.ps1`:

- `Fabric Data` — the six CSV files used to create Lakehouse tables.
- `BlobData` — one or more files to upload to the new ADLS Gen2 `data` container.

The subscription must be able to create the F16 capacity in West US 2 and the Foundry model deployments in West US.

#### Enable Azure resource providers

In the Azure portal, open **Subscriptions** → select the deployment subscription → **Resource providers**. Search for and register these namespaces if their status is not **Registered**:

- `Microsoft.Fabric` — Fabric F16 capacity.
- `Microsoft.Storage` — ADLS Gen2 Storage account and container.
- `Microsoft.CognitiveServices` — Foundry account, project, and model deployments.

Alternatively, after signing in to Azure CLI with an identity that can register providers, run:

```powershell
az provider register --namespace Microsoft.Fabric --wait
az provider register --namespace Microsoft.Storage --wait
az provider register --namespace Microsoft.CognitiveServices --wait
```

#### 2. Open the exact deployment folder

Open PowerShell 7. Set `$repoRoot` to the complete folder where **you** cloned `Sellers-Customer-Technical-Workshops` (for example, `C:\Repos\Sellers-Customer-Technical-Workshops`), then run:

```powershell
$repoRoot = "C:\path\to\Sellers-Customer-Technical-Workshops"
Set-Location (Join-Path $repoRoot "Ubiquitous-Innovation\FabricAutomation")
Get-Location
```

The displayed location must end with `Ubiquitous-Innovation\FabricAutomation`.

#### 3. Create and store the environment file

Create `.env` **inside this `FabricAutomation` folder**, at the same level as `up.ps1`. It is a local-only file and must not be committed or copied outside the deployment machine.

```powershell
Copy-Item .env.example .env
notepad .env
```

#### 4. Enter the `.env` values

Replace every placeholder in the opened `.env` file:

```dotenv
AZURE_SUBSCRIPTION_ID=<SUBSCRIPTION_GUID>
AZURE_TENANT_ID=<TENANT_GUID>
AZURE_CLIENT_ID=<SERVICE_PRINCIPAL_APPLICATION_CLIENT_ID>
AZURE_CLIENT_SECRET=<SERVICE_PRINCIPAL_CLIENT_SECRET>
AZURE_LOCATION=westus2
AZURE_RESOURCE_GROUP=rg-Ubiquitous
FABRIC_CAPACITY_ADMIN_UPN=<USER_UPN_TO_ADMINISTER_THE_CAPACITY_AND_WORKSPACE>
```

| `.env` entry | Enter this value |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | The Azure subscription GUID where the resources will be created. |
| `AZURE_TENANT_ID` | The Microsoft Entra tenant GUID containing the subscription and Fabric tenant. |
| `AZURE_CLIENT_ID` | Application (client) ID of the deployment service principal. |
| `AZURE_CLIENT_SECRET` | Active client secret value for that same service principal. |
| `AZURE_LOCATION` | Keep `westus2`; it is used for the resource group, capacity, and storage account. |
| `AZURE_RESOURCE_GROUP` | Keep exactly `rg-Ubiquitous`; the creation-only workflow validates this name. |
| `FABRIC_CAPACITY_ADMIN_UPN` | The user principal name that should see and administer the created Fabric workspace and capacity. |

Foundry and its model deployments use West US independently of `AZURE_LOCATION`.

#### 5. Save and run the complete deployment

Save and close Notepad. Return to the same PowerShell window, confirm it is still in the full `FabricAutomation` path, then run:

```powershell
Set-Location (Join-Path $repoRoot "Ubiquitous-Innovation\FabricAutomation")
.\up.ps1
```

The script uses `.env`, signs in to Azure, creates all resources, ingests the local data, and publishes the Fabric Data Agent.

This is deliberately **creation-only**. It stops before provisioning if `rg-Ubiquitous` already exists; it does not reuse, reassign, or overwrite an earlier deployment.

### What is created

| Location | Resource | Name / result |
|----------|----------|---------------|
| Azure, West US 2 | Resource group | `rg-Ubiquitous` |
| Azure, West US 2 | Fabric capacity | `fabricubiquitous<suffix>`; F16 SKU |
| Fabric | Workspace | `Ubiquitous-Innovation-<suffix>`, assigned only to the new capacity |
| Fabric | Lakehouse | `Ubiquitous_Lakehouse` by default; schema-enabled |
| Fabric | Lakehouse tables | Six CSV-backed tables plus `dbo.DimPlant` derived from the latest `Plant` observation |
| Fabric | Direct Lake semantic model | `Ubiquitous_Innovation_SemanticModel`; no report is created |
| Fabric | Published Data Agent | `Ubiquitous_Innovation_DataAgent` |
| Azure, West US 2 | ADLS Gen2 account | `adlsubiquitous<suffix>` with private `data` container populated from `BlobData` |
| Azure AI Foundry, West US | Foundry resource and project | `foundryubiquitous<suffix>` and `ubiquitous-innovation-project` |
| Azure AI Foundry, West US | Model deployments | `gpt5mini`, `gpt-5.4`, and `text-embedding-3-small` |
| Azure AI Foundry, West US | Prompt agent | `supply-chain-bi-agent`, using only `gpt5mini` with the instruction `You are my Supply chain agent.` |

The standalone `gpt-5.4` and embedding deployments are not connected to the dummy Foundry agent.

### Expected completion output

Names contain a random five-character lowercase-alphanumeric suffix. A successful run ends with output similar to:

```text
Uploaded <n> file(s) to the ADLS Gen2 data container.
Created 7 Delta table(s) in the Lakehouse Tables area.
Creating and refreshing the Direct Lake semantic model...
Creating and publishing the Data Agent...
Creating the Foundry Supply Chain agent...
Completed. Storage account: adlsubiquitous<suffix>; Workspace: Ubiquitous-Innovation-<suffix>; Lakehouse: Ubiquitous_Lakehouse; Semantic model: Ubiquitous_Innovation_SemanticModel; Data Agent: Ubiquitous_Innovation_DataAgent; Foundry project: ubiquitous-innovation-project; Foundry agent: SupplyChainAgent
```

### Where to verify the deployment

- **Azure portal**: Open **Resource groups** → `rg-Ubiquitous`. You will see the Fabric capacity, ADLS Gen2 storage account, and Foundry resource. Open the storage account → **Data storage** → **Containers** → `data` to verify the `BlobData` upload.
- **Microsoft Fabric**: Open [Fabric](https://app.fabric.microsoft.com/) → **Workspaces** → `Ubiquitous-Innovation-<suffix>`. The workspace contains `Ubiquitous_Lakehouse`, `Ubiquitous_Innovation_SemanticModel`, and `Ubiquitous_Innovation_DataAgent`. Open the Lakehouse → **Tables** to see the ingested Delta tables.
- **Microsoft Foundry**: Open [Microsoft Foundry](https://ai.azure.com/) and select `ubiquitous-innovation-project` under the new `foundryubiquitous<suffix>` resource. **Models** shows the three deployments and **Agents** shows `supply-chain-bi-agent`.

---
