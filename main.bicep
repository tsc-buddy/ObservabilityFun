targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Prefix for all resource names. 2–8 characters.')
@minLength(2)
@maxLength(8)
param namePrefix string = 'obs'

@description('Tags applied to every resource.')
param tags object = {}

@description('Local administrator password for all VMs.')
@secure()
param adminPassword string

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var uniqueSuffix    = take(uniqueString(resourceGroup().id), 6)
var adminUsername   = 'azureadmin'
var vmSku           = 'Standard_D2s_v3'

// Resource names
var vnetName        = '${namePrefix}-vnet-${uniqueSuffix}'
var bastionNsgName  = '${namePrefix}-bastion-nsg-${uniqueSuffix}'
var internalNsgName = '${namePrefix}-internal-nsg-${uniqueSuffix}'
var bastionPipName  = '${namePrefix}-bastion-pip-${uniqueSuffix}'
var bastionHostName = '${namePrefix}-bastion-${uniqueSuffix}'
var lawName         = '${namePrefix}-law-${uniqueSuffix}'

// Windows computer names are capped at 15 characters
var win1Name  = take('${namePrefix}w1${uniqueSuffix}', 15)
var win2Name  = take('${namePrefix}w2${uniqueSuffix}', 15)
var linuxName = take('${namePrefix}l1${uniqueSuffix}', 64)

// Addressing
var vnetAddressPrefix    = '10.0.0.0/16'
var bastionSubnetPrefix  = '10.0.0.0/26'   // /26 minimum required for Bastion
var internalSubnetPrefix = '10.0.1.0/24'

// ---------------------------------------------------------------------------
// NSG – AzureBastionSubnet  (Microsoft-required rules)
// ---------------------------------------------------------------------------
resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: bastionNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      // ── Inbound ──────────────────────────────────────────────────────────
      {
        name: 'AllowHttpsInbound'
        properties: {
          priority: 120
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowGatewayManagerInbound'
        properties: {
          priority: 130
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          priority: 140
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionHostCommsInbound'
        properties: {
          priority: 150
          protocol: '*'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['8080', '5701']
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      // ── Outbound ─────────────────────────────────────────────────────────
      {
        name: 'AllowSshRdpOutbound'
        properties: {
          priority: 100
          protocol: '*'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['22', '3389']
        }
      }
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionCommunicationOutbound'
        properties: {
          priority: 120
          protocol: '*'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['8080', '5701']
        }
      }
      {
        name: 'AllowHttpOutbound'
        properties: {
          priority: 130
          protocol: '*'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '80'
        }
      }
      {
        name: 'DenyAllOutbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// NSG – internal subnet  (platform default-deny rules only; no custom rules)
// ---------------------------------------------------------------------------
resource internalNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: internalNsgName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

// ---------------------------------------------------------------------------
// Virtual Network
// ---------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
          networkSecurityGroup: { id: bastionNsg.id }
        }
      }
      {
        name: 'internal'
        properties: {
          addressPrefix: internalSubnetPrefix
          networkSecurityGroup: { id: internalNsg.id }
        }
      }
    ]
  }
}

// Shared subnet reference used by all VM NICs
var internalSubnetId = '${vnet.id}/subnets/internal'

// ---------------------------------------------------------------------------
// Public IP + Azure Bastion (Basic SKU)
// ---------------------------------------------------------------------------
resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: bastionPipName
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: bastionHostName
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: { id: '${vnet.id}/subnets/AzureBastionSubnet' }
          publicIPAddress: { id: bastionPip.id }
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Log Analytics Workspace
// ---------------------------------------------------------------------------
resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: lawName
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ---------------------------------------------------------------------------
// Network Interfaces  (private IPs only – access via Bastion)
// ---------------------------------------------------------------------------
resource win1Nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${win1Name}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: internalSubnetId }
        }
      }
    ]
  }
}

resource win2Nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${win2Name}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: internalSubnetId }
        }
      }
    ]
  }
}

resource linuxNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${linuxName}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: internalSubnetId }
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Windows VM 1
// ---------------------------------------------------------------------------
resource win1Vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: win1Name
  location: location
  tags: tags
  properties: {
    hardwareProfile: { vmSize: vmSku }
    osProfile: {
      computerName: win1Name
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: win1Nic.id }]
    }
  }
}

// ---------------------------------------------------------------------------
// Windows VM 2
// ---------------------------------------------------------------------------
resource win2Vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: win2Name
  location: location
  tags: tags
  properties: {
    hardwareProfile: { vmSize: vmSku }
    osProfile: {
      computerName: win2Name
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: win2Nic.id }]
    }
  }
}

// ---------------------------------------------------------------------------
// Linux VM  (Ubuntu 22.04 LTS Gen2)
// ---------------------------------------------------------------------------
resource linuxVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: linuxName
  location: location
  tags: tags
  properties: {
    hardwareProfile: { vmSize: vmSku }
    osProfile: {
      computerName: linuxName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: linuxNic.id }]
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output vnetId      string = vnet.id
output lawId       string = law.id
output bastionName string = bastionHost.name
output win1VmName  string = win1Vm.name
output win2VmName  string = win2Vm.name
output linuxVmName string = linuxVm.name
