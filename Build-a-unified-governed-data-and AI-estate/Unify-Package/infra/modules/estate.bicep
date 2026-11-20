param storageAccountName string
param storageLocation string
param sqlServerName string
param sqlLocation string
param sqlAdministratorLogin string
@secure()
param sqlAdministratorPassword string
param sqlDatabaseName string
param fabricCapacityName string
param fabricCapacityLocation string
param fabricCapacityAdministrators array
param deploymentPrincipalObjectId string
param deploymentPrincipalType string

var storageBlobDataContributorRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
)

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: storageLocation
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource dataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'data'
  properties: { publicAccess: 'None' }
}

// Source-data scripts use az storage --auth-mode login. Give that Azure CLI
// identity data-plane access without enabling shared keys on the storage account.
resource deploymentPrincipalStorageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, deploymentPrincipalObjectId, storageBlobDataContributorRoleDefinitionId)
  scope: storageAccount
  properties: {
    principalId: deploymentPrincipalObjectId
    principalType: deploymentPrincipalType
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
  }
}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: sqlLocation
  properties: {
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorPassword
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: '1.2'
  }
}

resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource operationalDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: sqlLocation
  sku: { name: 'Basic', tier: 'Basic' }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
  }
}

resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: fabricCapacityName
  location: fabricCapacityLocation
  sku: { name: 'F16', tier: 'Fabric' }
  properties: {
    administration: { members: fabricCapacityAdministrators }
  }
}

// Azure integration foundation for the BusinessApplication source domain. The Logic
// App and its SQL API connection are retained with the rest of the Azure foundation;
// this package does not create or invoke a Fabric SQL Database target.
resource integrationAccount 'Microsoft.Logic/integrationAccounts@2019-05-01' = {
  name: 'caldova-integration-account'
  location: sqlLocation
  sku: {
    name: 'Free'
  }
  // Required by the Microsoft.Logic resource contract even when no B2B artifacts
  // are configured yet.
  properties: {}
}

// The SQL API connection is retained as part of the Azure integration foundation.
// This package intentionally does not configure a runtime SQL target for it.
resource sqlConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'sql'
  location: sqlLocation
  kind: 'V1'
  properties: {
    displayName: 'sql'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', sqlLocation, 'sql')
    }
    // The SQL connector registers Managed Identity auth under the ID "oauthMI", not
    // the generic "managedIdentityAuth" name other connectors use.
    parameterValueSet: {
      name: 'oauthMI'
      values: {}
    }
  }
}

resource businessApplicationIngestLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'caldova-businessapp-ingest'
  location: sqlLocation
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    integrationAccount: {
      id: integrationAccount.id
    }
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          type: 'Object'
          defaultValue: {}
        }
        // These parameters remain as part of the retained Azure integration definition.
        // This package does not configure or invoke the workflow.
        sqlServer: { type: 'String', defaultValue: '' }
        sqlDatabase: { type: 'String', defaultValue: '' }
        // The integration definition retains the query parameter for a future Azure SQL target.
        customerDetailsQuery: { type: 'String', defaultValue: '' }
        customerAddressQuery: { type: 'String', defaultValue: '' }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {}
          }
        }
      }
      actions: {
        // The SQL connector's query/sql action does not reliably execute a multi-statement
        // batch (a DELETE followed by an INSERT...FROM OPENJSON(@json) WITH (...)) as one
        // call - it returned "Must declare the scalar variable @json" / "Incorrect syntax
        // near 'with'" when both statements were combined. Each statement now runs as its
        // own action instead.
        Delete_CustomerDetails: {
          type: 'ApiConnection'
          runAfter: {}
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sql\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'sqlServer\')))},@{encodeURIComponent(encodeURIComponent(parameters(\'sqlDatabase\')))}/query/sql'
            body: {
              query: 'DELETE FROM dbo.CustomerDetails;'
            }
          }
        }
        Load_CustomerDetails: {
          type: 'ApiConnection'
          runAfter: {
            Delete_CustomerDetails: ['Succeeded']
          }
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sql\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'sqlServer\')))},@{encodeURIComponent(encodeURIComponent(parameters(\'sqlDatabase\')))}/query/sql'
            body: {
              query: '@parameters(\'customerDetailsQuery\')'
            }
          }
        }
        Delete_CustomerAddress: {
          type: 'ApiConnection'
          runAfter: {
            Load_CustomerDetails: ['Succeeded']
          }
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sql\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'sqlServer\')))},@{encodeURIComponent(encodeURIComponent(parameters(\'sqlDatabase\')))}/query/sql'
            body: {
              query: 'DELETE FROM dbo.CustomerAddress;'
            }
          }
        }
        Load_CustomerAddress: {
          type: 'ApiConnection'
          runAfter: {
            Delete_CustomerAddress: ['Succeeded']
          }
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sql\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'sqlServer\')))},@{encodeURIComponent(encodeURIComponent(parameters(\'sqlDatabase\')))}/query/sql'
            body: {
              query: '@parameters(\'customerAddressQuery\')'
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          sql: {
            connectionId: sqlConnection.id
            connectionName: 'sql'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', sqlLocation, 'sql')
          }
        }
      }
    }
  }
}

output storageAccountName string = storageAccount.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = operationalDatabase.name
output fabricCapacityResourceId string = fabricCapacity.id
output businessApplicationLogicAppName string = businessApplicationIngestLogicApp.name
output businessApplicationLogicAppPrincipalId string = businessApplicationIngestLogicApp.identity.principalId
