# 🧑‍🏫 ObservabilityFun — Instructor Guide

This file contains the expected solutions, key decision points, and official documentation links for each lab task. Share this with facilitators only.

---

## Section 1 — Instrument the VMs

### Task 1.1 — Enable VM Insights

**Solution:**
1. Navigate to each VM → **Insights** → **Enable**
2. Select the existing Log Analytics Workspace
3. Azure Monitor Agent (AMA) is installed automatically as a VM extension (`AzureMonitorWindowsAgent` / `AzureMonitorLinuxAgent`)
4. Verify under VM → **Extensions + applications**

> ⚠️ VM Insights creates its own default DCR (`MSVMI-<workspace>`) covering performance and Map data — participants should be aware this exists alongside any DCRs they create manually.

**Docs:**
- [Enable VM Insights overview](https://learn.microsoft.com/azure/azure-monitor/vm/vminsights-enable-overview)
- [Azure Monitor Agent overview](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-overview)

---

### Task 1.2 — Windows Event Log DCR

**Solution:**
1. Azure Monitor → **Data Collection Rules** → **Create**
2. Platform: Windows. Associate both Windows VMs.
3. Under **Data sources** → Add → **Windows Event Logs**
4. Switch to **Custom** mode to specify individual Event IDs via XPath queries:

```
System!*[System[(EventID=7036 or EventID=7045 or EventID=1074)]]
Security!*[System[(EventID=4625 or EventID=4648 or EventID=4720 or EventID=4740)]]
```

5. **Destination**: Log Analytics Workspace → table `Event`

**Key point for participants:** XPath filtering reduces ingestion cost — only the specified Event IDs are collected, not entire channels.

**Docs:**
- [Collect Windows Event Logs with AMA](https://learn.microsoft.com/azure/azure-monitor/agents/data-collection-windows-events)
- [XPath query filtering](https://learn.microsoft.com/azure/azure-monitor/agents/data-collection-rule-overview#filtering-with-xpath-queries)

---

### Task 1.3 — Performance Counter DCR (all VMs)

**Solution:**
1. Create a new DCR (or add a data source to the existing one) — associate all 3 VMs
2. Add **Performance Counters** data source, switch to **Custom**

| Counter path | Sample rate |
|---|---|
| `\Processor(_Total)\% Processor Time` | 60s |
| `\Memory\Available MBytes` | 60s |
| `\LogicalDisk(*)\% Free Space` | 300s |
| `\PhysicalDisk(*)\Disk Transfers/sec` | 60s |
| `\PhysicalDisk(*)\Current Disk Queue Length` | 60s |
| `\Network Interface(*)\Bytes Total/sec` | 60s |

Linux equivalents (for the Ubuntu VM) use the same counter names — AMA handles the translation to `perf` under the hood.

3. Destination: Log Analytics → table `Perf`

**Docs:**
- [Collect performance counters with AMA](https://learn.microsoft.com/azure/azure-monitor/agents/data-collection-performance)
- [Perf table schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/perf)

---

### Task 1.4 — Linux Syslog DCR

**Solution:**
1. New DCR, Platform: Linux, associate the Linux VM
2. Data source: **Syslog**
3. Select facilities: `auth`, `authpriv`, `daemon`, `kern`
4. Minimum severity: **Warning**
5. Destination: Log Analytics → table `Syslog`

**Docs:**
- [Collect Syslog with AMA](https://learn.microsoft.com/azure/azure-monitor/agents/data-collection-syslog)
- [Syslog table schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/syslog)

---

## Section 2 — In-Guest Alerts (Log-based)

### Task 2.1 — Print Spooler stopped (Event ID 7036)

**Solution:**
1. Azure Monitor → **Alerts** → **Create alert rule**
2. Scope: Log Analytics Workspace (or individual VMs)
3. Condition: **Custom log search**
4. KQL:
```kql
Event
| where EventLog == "System"
| where EventID == 7036
| where RenderedDescription has "Print Spooler" and RenderedDescription has "stopped"
```
5. Evaluation: every 5 min, lookback 5 min, threshold >= 1

**Test:** Connect via Bastion → `Stop-Service Spooler`

**Docs:**
- [Create a log search alert rule](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-create-log-alert-rule)
- [Event table schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/event)

---

### Task 2.2 — New service installed (Event ID 7045)

**KQL:**
```kql
Event
| where EventLog == "System"
| where EventID == 7045
| project TimeGenerated, Computer, RenderedDescription
```
Same alert setup as 2.1, threshold >= 1.

**Docs:** Same as Task 2.1.

---

### Task 2.3 — Brute-force failed logons (Event ID 4625)

**KQL:**
```kql
SecurityEvent
| where EventID == 4625
| summarize FailedLogons = count() by Computer, bin(TimeGenerated, 5m)
| where FailedLogons > 5
```

> ⚠️ Note: Security events land in the `SecurityEvent` table (when the Security channel is collected), not the generic `Event` table.

**Test:** Attempt several failed logons via Bastion RDP.

**Docs:**
- [SecurityEvent table schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/securityevent)

---

### Task 2.4 — Account lockout (Event ID 4740)

**KQL:**
```kql
SecurityEvent
| where EventID == 4740
| project TimeGenerated, Computer, TargetAccount, SubjectUserName
```
Threshold >= 1.

---

### Task 2.5 — Low memory alert (in-guest)

**KQL:**
```kql
Perf
| where ObjectName == "Memory"
| where CounterName == "Available MBytes"
| where CounterValue < 500
| project TimeGenerated, Computer, CounterValue
```
Evaluation: every 5 min, lookback 5 min, threshold >= 1 result.

---

### Task 2.6 — Disk queue length > 5

**KQL:**
```kql
Perf
| where ObjectName == "PhysicalDisk"
| where CounterName == "Current Disk Queue Length"
| where InstanceName != "_Total"
| where CounterValue > 5
```
Evaluation: every 5 min, lookback 5 min.

**Discussion point:** Sustained queue length > 1–2 per spindle is typically a red flag. On SSDs the threshold can be higher before visible impact, but it remains a saturation signal.

**Docs:**
- [Perf table schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/perf)

---

### Task 2.7 — Missing heartbeat

**KQL:**
```kql
Heartbeat
| summarize LastHeartbeat = max(TimeGenerated) by Computer
| where LastHeartbeat < ago(5m)
```

**Docs:**
- [Heartbeat table schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/heartbeat)

---

## Section 3 — Platform / Host Metric Alerts

### Task 3.1 — VM Availability metric

**Solution:**
1. Alert rule → Scope: VM(s) or resource group
2. Signal: **VM Availability** (namespace: `Microsoft.Compute/virtualMachines`)
3. Threshold: < 1 (i.e., equals 0)
4. Aggregation: Average, period 1 min

**Docs:**
- [Supported metrics: Microsoft.Compute/virtualMachines](https://learn.microsoft.com/azure/azure-monitor/reference/metrics-index)
- [Create a metric alert rule](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-create-metric-alert-rule)

---

### Task 3.2 — Platform CPU vs in-guest CPU

**Solution:**
- Signal: **Percentage CPU**, threshold > 90%, aggregation Average, 5-min window

**Discussion notes for facilitators:**
- **Platform metric**: sourced from hypervisor, available ~1-min granularity, no agent needed, always available even if the OS is hung
- **In-guest `% Processor Time`**: sourced from inside the OS via AMA/DCR, reflects actual OS scheduler view, may disagree with platform metric (e.g. when steal time or balloon driver is involved)
- Platform alerts are generally lower latency but less granular (per-VM only, not per-core/process)

**Docs:**
- [Platform vs guest metrics](https://learn.microsoft.com/azure/azure-monitor/vm/monitor-virtual-machine-data-collection#compare-metrics-and-logs)

---

### Task 3.3 — OS Disk IOPS Consumed Percentage

**Solution:**
- Signal: **OS Disk IOPS Consumed Percentage**
- Threshold > 95%, Average, 5-min window

**Docs:** Same metrics index link as Task 3.1.

---

## Section 4 — Action Groups & Alert Operations

### Task 4.1 — Action Group

**Solution:**
1. Azure Monitor → **Action groups** → **Create**
2. Add action: **Email/SMS/Push/Voice** → enter email address
3. Attach to all alert rules via the **Actions** tab when creating/editing each rule

**Docs:**
- [Create and manage action groups](https://learn.microsoft.com/azure/azure-monitor/alerts/action-groups)

---

### Task 4.2 — Severity guidance

Suggested severity assignments (for discussion — there's no single right answer):

| Alert | Suggested Sev |
|---|---|
| VM Availability = 0 | Sev 1 |
| Heartbeat missing > 5 min | Sev 1 |
| Failed logons > 5 in 5 min | Sev 2 |
| Account lockout | Sev 2 |
| CPU > 90% | Sev 2 |
| Available memory < 500 MB | Sev 2 |
| Disk queue > 5 | Sev 3 |
| OS Disk IOPS > 95% | Sev 2 |
| Print Spooler stopped | Sev 3 |
| New service installed | Sev 3 |

---

### Task 4.3 — Alert Processing Rules (suppression)

**Solution:**
1. Azure Monitor → **Alert processing rules** → **Create**
2. Scope: resource group
3. Rule type: **Suppression**
4. Schedule: Weekly, Sunday 02:00–04:00 UTC

**Docs:**
- [Alert processing rules](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-processing-rules)

---

## Section 5 — Multi-Resource Alerting

### Task 5.1 — Single alert rule targeting all VMs

**Solution:**
- When creating the alert rule, set scope to the **resource group** rather than a single VM
- For metric alerts, Azure Monitor evaluates the condition per-resource automatically and fires per VM
- For log search alerts, the KQL already returns results across all VMs — use `Computer` as the split dimension

**Discussion:** Per-resource scope is easier to manage at scale. Per-VM rules give more granular control but create alert sprawl.

**Docs:**
- [Monitor multiple resources with one alert rule](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-metric-multiple-time-series-single-rule)

---

### Task 5.2 — Log search vs metric alert architecture

**Key teaching points:**
- **Metric alerts**: evaluated against the metrics pipeline (near real-time, ~1-min resolution). Fire quickly, low cost.
- **Log search alerts**: evaluated on a schedule (minimum 1 min) against Log Analytics. Ingestion latency (typically 2–5 min) means end-to-end alert latency is higher.
- For the same CPU threshold — the platform metric alert will almost always fire first.
- Log search alerts are more expressive (arbitrary KQL, cross-table joins) but are fundamentally reactive.

**Docs:**
- [Types of Azure Monitor alerts](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-overview#types-of-alerts)

---

## Section 6 — NSG Flow Logs

### Task 6.1 — Enable NSG Flow Logs

**Solution:**
1. Network Watcher → **Flow logs** → **Create**
2. Select the internal subnet NSG
3. Storage account: create a new one (required even when sending to Log Analytics)
4. Enable **Traffic Analytics** and point to the Log Analytics Workspace
5. Data lands in the `AzureNetworkAnalytics_CL` table (Traffic Analytics enriched) or `NTANetAnalytics` table

> ℹ️ Raw flow logs go to storage. Traffic Analytics processes them and pushes to Log Analytics. There is a processing delay of ~10 minutes.

**Docs:**
- [NSG Flow Logs overview](https://learn.microsoft.com/azure/network-watcher/flow-logs-overview)
- [Traffic Analytics](https://learn.microsoft.com/azure/network-watcher/traffic-analytics)

---

### Task 6.2 — KQL: denied flows by source IP

```kql
AzureNetworkAnalytics_CL
| where TimeGenerated > ago(24h)
| where FlowStatus_s == "D"
| where FlowDirection_s == "I"
| summarize DeniedFlows = sum(toint(AllowedInFlows_d) + toint(DeniedInFlows_d)) by SrcIP_s
| sort by DeniedFlows desc
| take 20
```

> Exact column names vary slightly depending on Traffic Analytics schema version — participants may need to explore the table schema first.

---

## Section 7 — KQL Query Solutions

### Query 7.1 — Failed logons per VM (last 24h)
```kql
SecurityEvent
| where TimeGenerated > ago(24h)
| where EventID == 4625
| summarize FailedLogons = count() by Computer
| sort by FailedLogons desc
```

### Query 7.2 — Service state changes (last 1h)
```kql
Event
| where TimeGenerated > ago(1h)
| where EventLog == "System"
| where EventID == 7036
| project TimeGenerated, Computer, RenderedDescription
| sort by TimeGenerated desc
```

### Query 7.3 — Top 10 processes by CPU (InsightsMetrics)
```kql
InsightsMetrics
| where Namespace == "Process"
| where Name == "CpuPercentage"
| extend Tags = todynamic(Tags)
| extend ProcessName = tostring(Tags["process.name"])
| summarize AvgCPU = avg(Val) by ProcessName, Computer
| sort by AvgCPU desc
| take 10
```

### Query 7.4 — Available memory per VM (last 6h, 30-min bins)
```kql
Perf
| where TimeGenerated > ago(6h)
| where ObjectName == "Memory"
| where CounterName == "Available MBytes"
| summarize AvgMemMB = avg(CounterValue) by Computer, bin(TimeGenerated, 30m)
| render timechart
```

### Query 7.5 — Linux Syslog errors by facility (last 24h)
```kql
Syslog
| where TimeGenerated > ago(24h)
| where SeverityLevel in ("err", "crit", "alert", "emerg")
| summarize ErrorCount = count() by Facility
| sort by ErrorCount desc
```

### Query 7.6 — Heartbeat gap detection (last 24h)
```kql
Heartbeat
| where TimeGenerated > ago(24h)
| order by Computer, TimeGenerated asc
| serialize
| extend PrevHeartbeat = prev(TimeGenerated, 1)
| extend Gap = TimeGenerated - PrevHeartbeat
| where Gap > 10m
| project TimeGenerated, Computer, GapMinutes = Gap / 1m
| sort by GapMinutes desc
```

### Query 7.7 — Disk queue length > 2 (last 1h)
```kql
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "PhysicalDisk"
| where CounterName == "Current Disk Queue Length"
| where InstanceName != "_Total"
| where CounterValue > 2
| project TimeGenerated, Computer, InstanceName, CounterValue
| sort by TimeGenerated desc
```

### Query 7.8 — Denied inbound flows by destination port (last 24h)
```kql
AzureNetworkAnalytics_CL
| where TimeGenerated > ago(24h)
| where FlowDirection_s == "I"
| where FlowStatus_s == "D"
| summarize DeniedCount = count() by DestPort_d
| sort by DeniedCount desc
| take 20
```

---

## 📚 Key Documentation Index

| Topic | Link |
|---|---|
| Azure Monitor overview | [learn.microsoft.com/.../monitor-overview](https://learn.microsoft.com/azure/azure-monitor/fundamentals/overview) |
| Azure Monitor Agent | [learn.microsoft.com/.../azure-monitor-agent-overview](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-overview) |
| Data Collection Rules | [learn.microsoft.com/.../data-collection-rule-overview](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview) |
| VM Insights | [learn.microsoft.com/.../vminsights-overview](https://learn.microsoft.com/azure/azure-monitor/vm/vminsights-overview) |
| Collect Windows Event Logs | [learn.microsoft.com/.../data-collection-windows-events](https://learn.microsoft.com/azure/azure-monitor/agents/data-collection-windows-events) |
| Collect performance counters | [learn.microsoft.com/.../data-collection-performance](https://learn.microsoft.com/azure/azure-monitor/agents/data-collection-performance) |
| Collect Syslog | [learn.microsoft.com/.../data-collection-syslog](https://learn.microsoft.com/azure/azure-monitor/agents/data-collection-syslog) |
| Create log search alert | [learn.microsoft.com/.../alerts-create-log-alert-rule](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-create-log-alert-rule) |
| Create metric alert | [learn.microsoft.com/.../alerts-create-metric-alert-rule](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-create-metric-alert-rule) |
| Action groups | [learn.microsoft.com/.../action-groups](https://learn.microsoft.com/azure/azure-monitor/alerts/action-groups) |
| Alert processing rules | [learn.microsoft.com/.../alerts-processing-rules](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-processing-rules) |
| Supported VM metrics | [learn.microsoft.com/.../metrics-index](https://learn.microsoft.com/azure/azure-monitor/reference/metrics-index) |
| NSG Flow Logs | [learn.microsoft.com/.../flow-logs-overview](https://learn.microsoft.com/azure/network-watcher/flow-logs-overview) |
| Traffic Analytics | [learn.microsoft.com/.../traffic-analytics](https://learn.microsoft.com/azure/network-watcher/traffic-analytics) |
| KQL quick reference | [learn.microsoft.com/.../kql-quick-reference](https://learn.microsoft.com/azure/data-explorer/kql-quick-reference) |
| Log Analytics tables reference | [learn.microsoft.com/.../tables/overview](https://learn.microsoft.com/azure/azure-monitor/reference/tables/tables-category) |
| Alert types overview | [learn.microsoft.com/.../alerts-overview](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-overview) |
