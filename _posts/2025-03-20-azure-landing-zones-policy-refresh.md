---
layout: post
title: "Azure Landing Zones Policy Refresh"
date: 2025-03-17 14:00:00 -0000
categories: [Azure]
tags: [Azure, Policy]
img_path: /assets/img/2025-03-20-alz-policy-refresh-part1/
---

I'm going to assume you already have the ALZ management group hierarchy configured as below.

![alz-mg](alz-mg.png)

Install the module

```powershell
Install-Module -Name EnterprisePolicyAsCode -Scope CurrentUser
```

Create the epac mg hierarchy. I want to create the new mg structure under Tenant Root Group with a prefix of "epac-".

```powershell
Copy-HydrationManagementGroupHierarchy -SourceGroupName "alz" -DestinationParentGroupName "<tenantId>" -Prefix "epac-"
```

![epac-mg](epac-mg.png)

Create a new repository or folder and open it in VS Code. Run the following command to create the necessary folder structure for the epac policies and an additional output folder.

```powershell
New-HydrationDefinitionsFolder -DefinitionsRootFolder Definitions

New-Item -Name Output -ItemType Directory
```

This will create the `Definitions` folder and subfolders, the `Output` folder and a `global-settings.jsonc` file.

![epac-tree](epac-tree.png)

Now that we have two alz mg setups, one for existing prod and one for epac dev, we can populate the `global-settings.jsonc` file with the required information by running the below command.

```powershell
$parameters = @{
    "PacOwnerId" = (New-Guid).Guid
    "ManagedIdentityLocation" = "westeurope"
    "MainPacSelector" = "epac-prod"
    "EpacPacSelector" = "epac-dev"
    "Cloud" = "AzureCloud"
    "TenantId" = "<tenantId>"
    "MainDeploymentRoot" = "/providers/Microsoft.Management/managementGroups/alz"
    "EpacDevelopmentRoot" = "/providers/Microsoft.Management/managementGroups/epac-alz"
    "DefinitionsRootFolder" = ".\Definitions"
    "Strategy" = "ownedOnly"
    "LogFilePath" = "."
}
New-HydrationGlobalSettingsFile @parameters
```

