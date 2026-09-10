targetScope = 'resourceGroup'

@description('Azure region for every resource')
param location string = resourceGroup().location

@description('Short lowercase prefix, 3-12 characters')
param prefix string

@description('Ubuntu administrative username')
param adminUsername string = 'labadmin'

@secure()
@description('Ubuntu password. Supply it at deployment time; never commit it.')
param adminPassword string

var suffix = toLower(uniqueString(resourceGroup().id, prefix))
var acrName = take(replace('${prefix}${suffix}acr', '-', ''), 50)
var lawName = '${prefix}-${suffix}-law'
var environmentName = '${prefix}-${suffix}-aca-env'
var keyVaultName = take('${prefix}-${suffix}-kv', 24)
var vnetName = '${prefix}-${suffix}-vnet'

resource natIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${prefix}-${suffix}-nat-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource natGateway 'Microsoft.Network/natGateways@2024-05-01' = {
  name: '${prefix}-${suffix}-nat'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natIp.id
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.40.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.40.0.0/26'
        }
      }
      {
        name: 'aca-infrastructure'
        properties: {
          addressPrefix: '10.40.2.0/23'
          delegations: [
            {
              name: 'aca-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'lab-vm'
        properties: {
          addressPrefix: '10.40.10.0/24'
          natGateway: {
            id: natGateway.id
          }
        }
      }
    ]
  }
}

resource bastionIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${prefix}-${suffix}-bastion-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: '${prefix}-${suffix}-bastion'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'bastion-ipconfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'AzureBastionSubnet')
          }
          publicIPAddress: {
            id: bastionIp.id
          }
        }
      }
    ]
  }
}

resource vmNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${prefix}-${suffix}-assessment-vm-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'lab-vm')
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: '${prefix}-${suffix}-assessment-vm'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'lakera-assessment-vm'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(loadTextContent('cloud-init.yaml'))
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: vmNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource acaEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'aca-infrastructure')
      internal: true
    }
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
  }
}

resource vmKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, vm.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    principalId: vm.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalType: 'ServicePrincipal'
  }
}

output registryName string = registry.name
output acaEnvironmentId string = acaEnvironment.id
output keyVaultName string = keyVault.name
output vmName string = vm.name
output bastionName string = bastion.name
