param dnsZoneName string
param staticIp string
param virtualNetworkId string
param linkName string

resource containerAppsDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: dnsZoneName
  location: 'global'
}

resource containerAppsDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: containerAppsDnsZone
  name: linkName
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

resource containerAppsDnsWildcard 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: containerAppsDnsZone
  name: '*'
  properties: {
    ttl: 60
    aRecords: [
      {
        ipv4Address: staticIp
      }
    ]
  }
}
