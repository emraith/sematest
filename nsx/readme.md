# Export-NsxtVmTagsToCsv.ps1

PowerShell script that connects to an NSX-T manager, retrieves all fabric virtual machines and their tags, and exports the data to a CSV file.

## What it does

- Connects to the NSX-T Manager REST API using HTTP Basic Authentication
- Fetches all virtual machines from the fabric inventory (with pagination, so large environments are fully retrieved)
- Outputs one row per VM with columns: **DisplayName**, **ExternalId**, **Tags**
- Tags are concatenated into a single column, separated by `;`. Each tag is formatted as:
  - `scope:tag` when the tag has a non-empty scope string (e.g. `os:linux`, `env:prd`)
  - `:tag` when scope is missing or an empty string `""` (e.g. `:value`)
  - Whitespace-only scopes (e.g. a single space `" "`) are **not** treated as empty: they are written literally as `scope:tag`, so a one-space scope with tag `mytag` appears as ` :mytag` (space, colon, then the tag value).
- **Excluded scopes:** Tags with scope `data.protection.requirements` or `licensed.os` are omitted from the export. VMs that have only these tags still appear in the CSV with an empty **Tags** cell.
- Example Tags cell: `os:linux;env:prd;:value; :spaceScopedTag` — the last segment is a space character as the scope (easy to miss when reading; the CSV field may be quoted by `Export-Csv` when needed).

## Requirements

- **PowerShell:** Windows PowerShell 5.1 or PowerShell 6+ (Core)
- **No extra modules:** Uses only built-in `Invoke-RestMethod` and standard cmdlets
- **NSX-T:** A reachable NSX-T manager with an account that can call the fabric virtual-machines API

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `NsxtManager` | Yes | FQDN or IP address of the NSX-T manager (e.g. `nsxt.company.com` or `192.168.1.10`) |
| `Credential` | No | PSCredential for API Basic Auth. If omitted, you will be prompted. |
| `OutputPath` | Yes | Path for the output CSV file (e.g. `.\vm-tags.csv`) |
| `SkipCertificateCheck` | No | Skip TLS certificate validation. Use only for lab or self-signed certs. Supported in PowerShell 6+; on 5.1 a warning is shown and the switch is ignored. |

## Usage examples

**Prompt for credentials:**

```powershell
.\Export-NsxtVmTagsToCsv.ps1 -NsxtManager 'nsxt.company.com' -OutputPath '.\vm-tags.csv'
```

**Pass credentials and skip certificate check (e.g. self-signed):**

```powershell
.\Export-NsxtVmTagsToCsv.ps1 -NsxtManager '192.168.1.10' -OutputPath '.\vm-tags.csv' -Credential (Get-Credential) -SkipCertificateCheck
```

**Verbose output (per-page fetch progress):**

```powershell
.\Export-NsxtVmTagsToCsv.ps1 -NsxtManager 'nsxt.company.com' -OutputPath '.\vm-tags.csv' -Verbose
```

## Console output

The script writes progress to the console:

- Connecting to the NSX-T manager
- Total VMs retrieved from NSX-T
- Processing count before export
- Export complete message with row count and file path

## Output CSV format

| DisplayName | ExternalId | Tags                    |
|------------|------------|-------------------------|
| vm-01      | uuid-1     | os:linux;env:prd;:value |
| vm-02      | uuid-2     |                         |

- One row per VM. VMs with no tags (or only excluded scopes: `data.protection.requirements`, `licensed.os`) have an empty **Tags** cell.
- **ExternalId** is the VM’s instance UUID (e.g. from vCenter).

## Errors

- Failed API calls (auth, network, server errors) are written to the error stream and the script exits with code `1`.
- On Windows PowerShell 5.1, `-SkipCertificateCheck` is not supported; the script warns and continues without skipping certificate validation.
