@description('Name of the Fabric capacity. The deployment intentionally creates no other resources.')
param capacityName string

@description('Azure region for the Fabric capacity.')
param location string

@description('UPN of the person who administers the Fabric capacity.')
param capacityAdministratorUpn string

@description('Object ID of the service principal that runs this deployment.')
param deploymentServicePrincipalObjectId string

resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: capacityName
  location: location
  sku: {
    name: 'F16'
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: [
        capacityAdministratorUpn
        deploymentServicePrincipalObjectId
      ]
    }
  }
}

output fabricCapacityName string = fabricCapacity.name
output fabricCapacityResourceId string = fabricCapacity.id
