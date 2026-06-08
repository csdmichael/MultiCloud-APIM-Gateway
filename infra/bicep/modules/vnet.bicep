// =============================================================================
// Multi-Cloud APIM Gateway — VNet + APIM-required NSG
// -----------------------------------------------------------------------------
// Purpose:
//   Internal VNET APIM requires a dedicated subnet with a Network Security
//   Group that allows the inbound/outbound ports documented at
//   https://learn.microsoft.com/azure/api-management/api-management-using-with-internal-vnet
//
// Notes:
//   * Inbound 3443 (Management) is REQUIRED from ApiManagement service tag.
//   * Inbound 6390 (Load balancer health probe) on TCP 6390 from AzureLoadBalancer.
//   * Inbound 443 from VirtualNetwork for client traffic.
//   * Outbound to Storage, SQL, AzureKeyVault, AzureMonitor.
// =============================================================================

@description('Azure region.')
param location string

@description('VNet name.')
param vnetName string

@description('APIM subnet name.')
param apimSubnetName string = 'snet-apim'

@description('VNet address space (CIDR).')
param vnetAddressPrefix string = '10.50.0.0/16'

@description('APIM subnet address space (CIDR). Must be a /27 or larger.')
param apimSubnetPrefix string = '10.50.1.0/27'

@description('Tags applied to all resources.')
param tags object = {}

// -------- NSG with APIM required rules --------
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${vnetName}-${apimSubnetName}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowApimManagement'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowAzureLoadBalancerProbe'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '6390'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowClientHttps'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowStorageOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
        }
      }
      {
        name: 'AllowSqlOutbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'SQL'
        }
      }
      {
        name: 'AllowKeyVaultOutbound'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureKeyVault'
        }
      }
      {
        name: 'AllowAzureMonitorOutbound'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '443'
            '1886'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureMonitor'
        }
      }
    ]
  }
}

// -------- VNet + APIM subnet --------
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: apimSubnetName
        properties: {
          addressPrefix: apimSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          // APIM stv2 requires explicit delegation? Not delegated — Microsoft.ApiManagement
          // uses subnet via VirtualNetworkConfiguration; no delegation needed for stv2.
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.KeyVault'
            }
            {
              service: 'Microsoft.Sql'
            }
            {
              service: 'Microsoft.EventHub'
            }
          ]
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output apimSubnetId string = '${vnet.id}/subnets/${apimSubnetName}'
output nsgId string = nsg.id
