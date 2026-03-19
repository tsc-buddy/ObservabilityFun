# 🧪 ObservabilityFun — Lab Guide

Welcome! This lab takes a vanilla Azure VM environment and challenges you to build **full observability** from the ground up using Azure Monitor. There are no step-by-step instructions here — the goal is to explore, figure it out, and understand *why* each piece fits together.

> 💡 **Everything in this lab can be done through the Azure Portal (click-ops). You do not need to write any code or Bicep unless you want to.**
>
> Use **GitHub Copilot** in VS Code to help you write KQL queries when you get to that section.

---

## 🏁 Your starting point

You have:
- A Log Analytics Workspace
- 2× Windows Server 2022 VMs
- 1× Ubuntu 22.04 LTS VM
- Azure Bastion for VM access (no public IPs on the VMs)

No monitoring agents are installed. No data is flowing. That's your job.

---

## 📦 Section 1 — Instrument the VMs

**Task 1.1**
Enable VM Insights on all three VMs and verify that the Azure Monitor Agent is successfully installed.

**Task 1.2**
Create a Data Collection Rule (DCR) and associate it with the **Windows VMs** to collect the following Windows Event Log channels:
- **System** — Event IDs: `7036` (service state change), `7045` (new service installed), `1074` (system shutdown/restart)
- **Security** — Event IDs: `4625` (failed logon), `4648` (explicit credential logon), `4720` (user account created), `4740` (account lockout)

**Task 1.3**
Extend your DCR (or create a new one) to collect **in-guest performance counters** from all three VMs:

| Counter | Object |
|---|---|
| `% Processor Time` | Processor |
| `Available MBytes` | Memory |
| `% Free Space` | LogicalDisk |
| `Disk Transfers/sec` | PhysicalDisk |
| `Current Disk Queue Length` | PhysicalDisk |
| `Bytes Total/sec` | Network Interface |

**Task 1.4**
Create a DCR targeting the **Linux VM** to collect Syslog from the following facilities at **Warning** severity and above:
`auth`, `authpriv`, `daemon`, `kern`

---

## 🔔 Section 2 — In-Guest Alerts (Log-based)

These alerts use data flowing through your DCRs into Log Analytics. No agent = no data = no alert. Make sure Section 1 is complete first.

**Task 2.1**
Use Azure Monitor to create a log search alert that fires when the **Print Spooler service stops** on any Windows VM.
- Source: Windows Event Log, Event ID `7036`
- The event message will contain `param1=Print Spooler` and `param2=stopped`
- Test it: connect via Bastion and stop the service manually

**Task 2.2**
Create an alert that fires when **any new service is installed** on a Windows VM (Event ID `7045`).

**Task 2.3**
Create an alert that fires when **more than 5 failed logon attempts** (Event ID `4625`) are detected against a single VM within a 5-minute window.
- Test it: attempt several failed RDP-style logins via Bastion

**Task 2.4**
Create an alert that fires when an **account lockout** (Event ID `4740`) is detected.

**Task 2.5**
Create an alert that fires when **available memory drops below 500 MB** on any VM, using the in-guest `Available MBytes` performance counter collected by your DCR.

**Task 2.6**
Create an alert that fires when **Current Disk Queue Length exceeds 5** sustained over 5 minutes on any VM.
> 💡 Disk queue length is a saturation indicator — spikes here often precede visible performance degradation.

**Task 2.7**
Create an alert that fires when a VM **heartbeat is missing for more than 5 minutes**.

---

## 📡 Section 3 — Platform / Host Metric Alerts

These alerts use Azure's platform metrics pipeline — **no agent or DCR required**. The data comes from the hypervisor layer.

**Task 3.1**
Create a metric alert that fires when **VM Availability** drops to `0` for any VM.

**Task 3.2**
Create a metric alert that fires when **Percentage CPU** (platform metric) exceeds `90%` for 5 minutes.
> Then compare: how does this alert behave differently to the in-guest `% Processor Time` alert from Task 2? What latency, granularity and scope differences do you notice?

**Task 3.3**
Create a metric alert that fires when **OS Disk IOPS Consumed Percentage** exceeds `95%`.

---

## 🔑 Section 4 — Action Groups & Alert Operations

**Task 4.1**
Create an **Action Group** that sends an email notification when triggered. Attach it to all alert rules you have created.

**Task 4.2**
Assign a meaningful **severity level (Sev 0–4)** to each of your alert rules and document your reasoning. Is a missing heartbeat a Sev 1 or Sev 2? Is a disk queue spike a Sev 3?

**Task 4.3**
Create an **Alert Processing Rule** that would suppress all alerts during a defined maintenance window (e.g. Sundays 02:00–04:00 UTC). You don't need to wait for Sunday — just configure the rule and understand how it sits above individual alert rules.

---

## 📊 Section 5 — Multi-Resource Alerting & Architecture

**Task 5.1**
Re-configure your CPU alert so it targets **all VMs in the resource group** with a single alert rule, rather than one rule per VM. Compare this pattern to the per-resource approach and think about the trade-offs.

**Task 5.2**
Review your alert rules and categorise each one:

| Type | Description |
|---|---|
| **Log search alert** | Evaluates a KQL query against Log Analytics on a schedule |
| **Metric alert** | Evaluates against the platform metrics pipeline in near real-time |

For the same symptom (e.g. high CPU), which alert type fires first? Why?

---

## 🌐 Section 6 — NSG Flow Logs

**Task 6.1**
Enable **NSG Flow Logs** on the `internal` subnet NSG and send the data to your Log Analytics Workspace.

**Task 6.2**
Once data is flowing, write a KQL query (use GitHub Copilot to help) that counts **denied flows by source IP** over the last 24 hours.

---

## 🤖 Section 7 — KQL Queries with GitHub Copilot

Open Log Analytics in the Azure Portal and use **GitHub Copilot in VS Code** to help you write and refine the following queries. Don't just copy-paste — understand what each query does.

> 💡 Tip: open a `.kql` file in VS Code and describe what you want in a comment. Let Copilot suggest the query, then validate it in the portal.

**Query 7.1**
Count failed logon attempts (Event ID `4625`) per VM over the last 24 hours, sorted descending.

**Query 7.2**
List every service state change (Event ID `7036`) in the last hour across all Windows VMs.

**Query 7.3**
Show the top 10 processes by average CPU across all VMs using the `InsightsMetrics` table.

**Query 7.4**
Summarise average available memory per VM over the last 6 hours, binned in 30-minute intervals.

**Query 7.5**
Count error-level Syslog entries from the Linux VM by facility for the last 24 hours.

**Query 7.6**
Detect heartbeat gaps — find any VM that was silent for more than 10 minutes at any point in the last 24 hours.

**Query 7.7**
Show `Current Disk Queue Length` values greater than 2 over the last hour, grouped by VM and disk.

**Query 7.8**
Using NSG flow log data, count denied inbound flows by destination port over the last 24 hours.

---

## ✅ Done?

If you've worked through all seven sections you have:
- Full in-guest telemetry flowing into Log Analytics
- Platform metric coverage with no agent dependency
- Alerts covering availability, performance, security events and service health
- Suppression and multi-resource alerting patterns in place
- A set of KQL queries you wrote and understand

Nice work. 🎉
