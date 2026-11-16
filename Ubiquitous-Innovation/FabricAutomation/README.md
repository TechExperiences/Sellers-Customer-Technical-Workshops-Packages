# Fabric, Lakehouse, storage, and Foundry provisioning

Create `.env` from `.env.example`, replace the placeholders, then run:

```powershell
.\up.ps1
```

The script uses the configured service principal for non-interactive Azure CLI sign-in. If Azure CLI is already signed in as that exact application in the configured tenant, it reuses the existing session; otherwise it signs in silently.

The `Fabric Data` folder beside `up.ps1` is read locally. Each CSV is written once as a Delta table in the new Lakehouse `Tables` area; the CSV files are not uploaded to `Files`. Table names use the CSV filenames (for example, `Inventory.csv` becomes `Inventory`). The pipeline also derives `dbo.DimPlant` from the latest observation for each `PlantID`, so the semantic model can use `Plant` as a unique dimension.

The `BlobData` folder beside `up.ps1` is uploaded recursively to the `data` container in a new ADLS Gen2 storage account. Both source paths are resolved from the project directory, so the project can be copied to a VM without hardcoded user paths.

The workflow is creation-only and stops if `rg-Ubiquitous` already exists. It creates only:

1. `rg-Ubiquitous`
2. One F16 Fabric capacity with a random five-character alphanumeric suffix
3. One paired `Ubiquitous-Innovation-<suffix>` Fabric workspace
4. One schema-enabled Lakehouse
5. One ADLS Gen2 storage account named `adlsubiquitous<suffix>` and its `data` container
6. One Direct Lake semantic model: `Ubiquitous_Innovation_SemanticModel`
7. One published Data Agent: `Ubiquitous_Innovation_DataAgent`
8. One Azure AI Foundry account and project in West US
9. One low-capacity `gpt-5-mini` (`2025-08-07`) Global Standard deployment: `gpt5mini`
10. One Foundry prompt agent: `supply-chain-bi-agent`, with the instruction `You are my Supply chain agent.` Its endpoint enables the Responses and Activity protocols with Entra and Bot Service RBAC authorization schemes.

The service principal creates the workspace and Lakehouse. `FABRIC_CAPACITY_ADMIN_UPN` is added as a capacity administrator and workspace `Admin`, so that user can see and open the new workspace normally in the Fabric portal.

The semantic model contains the six Lakehouse `dbo` tables and their Product/Plant relationships. It is refreshed after creation so the published Data Agent can query it. No report is created.

Prerequisites: Azure CLI, Python, Azure RBAC that permits the service principal to create the resource group, Fabric capacity, storage account, Foundry account/project/model deployment, and role assignments (for example, Owner or Contributor plus User Access Administrator). The subscription must have quota for `gpt-5-mini` Global Standard in West US. The Fabric tenant must permit service principals to use Fabric APIs. For the Direct Lake refresh, allow the application to call Power BI APIs and grant the Power BI Service **Application** permission `Dataset.ReadWrite.All` with tenant admin consent. Microsoft Graph **Application** permission `User.Read.All` with tenant admin consent is required only to resolve `FABRIC_CAPACITY_ADMIN_UPN` before adding that user to the new workspace; the project does not check or assign licenses. The pipeline grants `Storage Blob Data Contributor` only to the service principal on its newly created storage account, and grants `Foundry User` only on the new Foundry project to both the service principal and `FABRIC_CAPACITY_ADMIN_UPN`.

---

## Deployment guide

### Run from the VS Code integrated terminal

1. Start **Visual Studio Code** and select **File** → **Open Folder**. Choose the cloned `Sellers-Customer-Technical-Workshops` repository folder.
2. Select **Terminal** → **New Terminal**. The terminal opens at the bottom of VS Code.
3. Set your cloned-repository path and move to this package folder:

```powershell
$repoRoot = "C:\path\to\Sellers-Customer-Technical-Workshops"
Set-Location (Join-Path $repoRoot "Ubiquitous-Innovation\FabricAutomation")
```

4. Create `.env` on the first run, then edit it in VS Code:

```powershell
Copy-Item .env.example .env
code .env
```

5. Save `.env`, return to the same terminal, and run `./up.ps1`:

```powershell
.\up.ps1
```

```mermaid
flowchart LR
    A[Open repository in VS Code] --> B[Terminal: New Terminal]
    B --> C[Move to FabricAutomation]
    C --> D[Create and edit .env]
    D --> E[Run up.ps1]
    E --> F[Review completed output]
```

### 1. Confirm the local tools and source folders

Use PowerShell 7 with Azure CLI (`az`) and Python 3 available in the terminal. Keep the supplied source folders beside `up.ps1`:

- `Fabric Data` — the six CSV files used to create Lakehouse tables.
- `BlobData` — one or more files to upload to the new ADLS Gen2 `data` container.

The subscription must be able to create the F16 capacity in West US 2 and the Foundry model deployments in West US.

### Enable Azure resource providers

In Azure portal, open **Subscriptions** → select the deployment subscription → **Resource providers**. Register these namespaces if their status is not **Registered**:

- `Microsoft.Fabric`
- `Microsoft.Storage`
- `Microsoft.CognitiveServices`

Or run:

```powershell
az provider register --namespace Microsoft.Fabric --wait
az provider register --namespace Microsoft.Storage --wait
az provider register --namespace Microsoft.CognitiveServices --wait
```

### 2. Open this deployment folder

Set `$repoRoot` to the folder where you cloned `Sellers-Customer-Technical-Workshops`, then run:

```powershell
$repoRoot = "C:\path\to\Sellers-Customer-Technical-Workshops"
Set-Location (Join-Path $repoRoot "Ubiquitous-Innovation\FabricAutomation")
Get-Location
```

### 3. Create and edit `.env`

Create `.env` in this `FabricAutomation` folder, beside `up.ps1`. Keep it local and do not commit it.

```powershell
Copy-Item .env.example .env
notepad .env
```

Enter these values:

```dotenv
AZURE_SUBSCRIPTION_ID=<SUBSCRIPTION_GUID>
AZURE_TENANT_ID=<TENANT_GUID>
AZURE_CLIENT_ID=<SERVICE_PRINCIPAL_APPLICATION_CLIENT_ID>
AZURE_CLIENT_SECRET=<SERVICE_PRINCIPAL_CLIENT_SECRET>
AZURE_LOCATION=westus2
AZURE_RESOURCE_GROUP=rg-Ubiquitous
FABRIC_CAPACITY_ADMIN_UPN=<USER_UPN_TO_ADMINISTER_THE_CAPACITY_AND_WORKSPACE>
```

| Entry | Value |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | Azure subscription GUID for the deployment. |
| `AZURE_TENANT_ID` | Microsoft Entra tenant GUID. |
| `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` | Application ID and active secret for the deployment service principal. |
| `AZURE_LOCATION` | Keep `westus2`. |
| `AZURE_RESOURCE_GROUP` | Keep exactly `rg-Ubiquitous`. |
| `FABRIC_CAPACITY_ADMIN_UPN` | User principal name that administers the created capacity and workspace. |

### 4. Run the complete deployment

Save `.env`, remain in this folder, then run:

```powershell
Set-Location (Join-Path $repoRoot "Ubiquitous-Innovation\FabricAutomation")
.\up.ps1
```

The workflow is creation-only. It creates `rg-Ubiquitous`, an F16 capacity, ADLS Gen2 storage, a Fabric workspace and Lakehouse, Lakehouse tables, a Direct Lake semantic model, a published Data Agent, and a Foundry project with model deployments and the Supply Chain agent.

```mermaid
flowchart TB
    RG[rg-Ubiquitous] --> CAP[F16 Fabric capacity]
    RG --> ADLS[ADLS Gen2: data container]
    RG --> FOUNDRY[Foundry account and project]
    CAP --> WS[Fabric workspace]
    WS --> LH[Lakehouse and Delta tables]
    LH --> SM[Direct Lake semantic model]
    SM --> DA[Published Data Agent]
    FOUNDRY --> MODELS[Model deployments]
    FOUNDRY --> AGENT[Supply Chain agent]
```

### Verify the result

- **Azure portal** → **Resource groups** → `rg-Ubiquitous` for the capacity, storage account, and Foundry resource.
- **Microsoft Fabric** → **Workspaces** → `Ubiquitous-Innovation-<suffix>` for `Ubiquitous_Lakehouse`, `Ubiquitous_Innovation_SemanticModel`, and `Ubiquitous_Innovation_DataAgent`.
- **Microsoft Foundry** → `ubiquitous-innovation-project` for the model deployments and `supply-chain-bi-agent`.
