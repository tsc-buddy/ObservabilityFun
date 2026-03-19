# 🔭 ObservabilityFun

A single-file Bicep deployment that stands up a clean, vanilla Azure lab environment — perfect for experimenting with observability tooling without any pre-baked monitoring agents getting in the way.

---

## 🏗️ What it deploys

| Resource | Details |
|---|---|
| 🌐 Virtual Network | `10.0.0.0/16` with two subnets: `AzureBastionSubnet` (`/26`) and `internal` (`/24`) |
| 🔒 NSGs | Bastion NSG with all required Microsoft rules; internal NSG with platform defaults only |
| 🛡️ Azure Bastion | Basic SKU — sole access path to the VMs (no public IPs on VMs) |
| 🪟 Windows VMs × 2 | Windows Server 2022 Azure Edition, `Standard_D2s_v3`, Premium LRS |
| 🐧 Linux VM × 1 | Ubuntu 22.04 LTS Gen2, `Standard_D2s_v3`, Premium LRS |
| 📊 Log Analytics Workspace | PerGB2018 SKU, 30-day retention |

> ⚠️ No VM Insights, no monitoring extensions — everything is intentionally vanilla.

---

## ⚙️ Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `location` | `string` | RG location | Azure region for all resources |
| `namePrefix` | `string` | `obs` | Prefix for resource names (2–8 chars) |
| `tags` | `object` | `{}` | Tags applied to every resource |
| `adminPassword` | `securestring` | *(required)* | Local admin password for all VMs |

Local admin username is fixed as **`azureadmin`**.

---

## 📤 Outputs

| Output | Description |
|---|---|
| `vnetId` | Resource ID of the virtual network |
| `lawId` | Resource ID of the Log Analytics Workspace |
| `bastionName` | Name of the Azure Bastion host |
| `win1VmName` | Name of Windows VM 1 |
| `win2VmName` | Name of Windows VM 2 |
| `linuxVmName` | Name of the Linux VM |

---

## 🚀 Deploy

```bash
az deployment group create \
  --resource-group <your-rg> \
  --template-file main.bicep \
  --parameters namePrefix=obs adminPassword='<your-password>'
```

Resource names include a unique suffix derived from the resource group ID, so re-deploying to the same RG is idempotent. 🎉
