# Caldova unified estate: resource and data map

## Azure foundation

| Order | Resource | Proposed name | Region | Purpose |
|---:|---|---|---|---|
| 1 | Resource group | `rg-Build-Unify` | West US 2 | Single lifecycle boundary for all Azure resources. |
| 2 | Storage account | `stcaldova<unique-suffix>` | West US 3 | Landing zone for the three local source domains. |
| 3 | Blob container | `data` | Inherits storage account | Holds source data without modification. |
| 4 | Azure SQL logical server | `sql-operational-<unique-suffix>` | West US 2 | Hosts the operational source database. |
| 5 | Azure SQL database | `OperationalData` | West US 2 | Holds the eight operational tables. |
| 6 | Fabric capacity | `fabriccapacity<unique-suffix>` | West US 2 | F16 capacity, deployed inside `rg-Build-Unify`. |

## Storage landing layout

```text
data/
  Analytical/                 <- 13 CSV files from ./Analytical
  BusinessApplication/        <- CustomerDetails.json, CustomerAddress.json
  Operational/                <- 8 CSV files from ./Operational
```

## Domain mapping

| Local source | Landing zone | Initial target |
|---|---|---|
| `Analytical/*.csv` | `data/Analytical/` | Blob landing storage |
| `BusinessApplication/*.json` | `data/BusinessApplication/` | Blob landing storage |
| `Operational/*.csv` | `data/Operational/` | Azure SQL `OperationalData.dbo` tables |

## Verified data inventory

| Domain | Tables/files | Rows |
|---|---|---:|
| Analytical | 13 CSV files | 978 |
| Business Application | 2 JSON files | 50 |
| Operational | 8 CSV files | 328 |

All operational referential checks pass, including joins to the supplied analytical product, plant, and location dimensions.

## Provisioning prerequisite

The Azure identity used for deployment must have **Contributor** (or equivalent resource-create permission) at the target subscription or `rg-Build-Unify` scope. It also needs capacity-creation permission for `Microsoft.Fabric/capacities`.
