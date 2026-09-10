targetScope = 'resourceGroup'

param location string = resourceGroup().location
param appName string
param environmentId string
param registryName string

@secure()
param openAiApiKey string

@secure()
param labToken string

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: registryName
}

var credentials = registry.listCredentials()

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 8080
        transport: 'http'
      }
      registries: [
        {
          server: '${registry.name}.azurecr.io'
          username: credentials.username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          name: 'acr-password'
          value: credentials.passwords[0].value
        }
        {
          name: 'openai-key'
          value: openAiApiKey
        }
        {
          name: 'lab-token'
          value: labToken
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'hr-copilot'
          image: '${registry.name}.azurecr.io/hr-copilot:latest'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'PORT'
              value: '8080'
            }
            {
              name: 'OPENAI_API_KEY'
              secretRef: 'openai-key'
            }
            {
              name: 'LAB_TOKEN'
              secretRef: 'lab-token'
            }
            {
              name: 'LAB_VULNERABLE_MODE'
              value: 'true'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
}

output agentFqdn string = app.properties.configuration.ingress.fqdn
