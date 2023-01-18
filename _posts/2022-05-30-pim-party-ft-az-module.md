---
layout: post
title: "PIM Party ft. Az Module"
date: 2022-05-30 14:00:00 -0000
categories: [PIM, PowerShell]
tags: [Azure, PIM, PowerShell]
img_path: /assets/img/2022-05-30-pim-party-ft-az-module/
---

Privileged Identity Management (PIM) in Azure helps you manage and monitor access to your Azure resources. It’s a great service that lets you set up just-in-time access with additional security controls for your management groups, subscriptions or resource groups. It can also be used for Azure AD resources, but that’s outside of the scope of this post.

When we’re creating new Landing Zones in Azure, we want to automate as much as possible as it’s likely a task that will be done many times over when new stakeholders are onboarded to Azure, or you’re moving from a few big subscriptions to the Landing Zone approach.

This post will focus on automating the configuration of PIM, such as settings and assignments, using the Az module.

# Snack
Snack is a huge cat food retailer. They only sell one product, but it’s so addicting to the cats their slogan is literally:

![snack-meme](snack-meme.jpg)

Snack has a large footprint in Azure, where all the different teams and departments share one big subscription. Ordering a new resource group must be done using a ticketing system and go through IT, which has led to most teams just ordering one or few resource groups and filling them to the brim with resources.

Snack is now looking to redesign their Azure platform using the Landing Zone design principles. Each team or application will get their own Landing Zone subscription per needed environment (dev, test, qa or prod).

IT together with the differens teams have already identified that they need ~25 new Landing Zones.

# Subscription creation
Snack will be creating all new subscriptions using a Bicep template that is deployed using an Azure DevOps pipeline, where a Service Principal is used for authentication that has access to create subscriptions under the Enterprise Agreement.

<script src="https://gist.github.com/Hardstl/7620382bc83b92f3900e98e7956aa48f.js"></script>

Two parameters must be supplied before deployment, name and environment.

```powershell
# Assign parameter values to be passed to the Bicep template
$TemplateParameters = @{
    name        = "payroll"
    environment = "prod"
}

# Assign parameter values for New-AzManagementGroupDeployment
$Parameters = @{
    Name                    = "DeploySubscription"
    ManagementGroupId       = "mg-labstahl"
    Location                = "westeurope"
    TemplateFile            = ".\subscription.bicep"
    TemplateParameterObject = $TemplateParameters
}

# Deploy subscription
$Deploy = New-AzManagementGroupDeployment @Parameters

# Reference newly created subscription id
$Deploy.Outputs.subscriptionId
```

After running the Pipeline, a new subscription named **snack-payroll-prod** was created. The id of the subscription is available as an output that can later be referenced in other deployments.

# PIM ft. Az Module

Using the Az PowerShell module, Snack can now configure PIM for the newly created subscription by adding another stage in their Pipeline where they reference the subscription id for the next steps.

Below are the available cmdlets.

![azrolecmdlets](azrolecmdlets.png)

All the classes used in the `Update-AzRoleManagementPolicy` cmdlet can be found [here](https://docs.microsoft.com/en-us/dotnet/api/microsoft.azure.powershell.cmdlets.resources.authorization.models.api20201001preview?view=az-ps-latest). I’m going to focus on the below two:

`RoleManagementPolicyExpirationRule` \
Expiration settings; how long a user can be active or eligible for a role, or how long they can activate a certain role during the day.

`RoleManagementPolicyEnablementRule` \
Enablement settings; what controls must be satisfied for the user to grant access. For example, MFA or providing a justification.
 
Disclaimer: The official documentation has examples using these classes. However, during my testing I got errors when running the script. Luckily I got some help from my dear colleague [Bjompen](https://twitter.com/bjompen) who showed me how to use full class names. *(Hint: Ctrl + Space inside the brackets of the class).*

For example:

Docs: \
`[RoleManagementPolicyExpirationRule]`

Full: \
`[Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Models.Api20201001Preview.RoleManagementPolicyExpirationRule]`

## Configure PIM settings

Snack’s IT wants all PIM settings to look the same for all new Landing Zones, and the below default settings are not cutting it. They start by configuring the PIM settings for the Contributor role on the new subscription.

![pim-settings](pim-settings.png)

### End user settings (Activation blade in PIM)

When configuring these settings we must target the specific rule id that relates to a specific setting. To demonstrate this, I’ve made this very professional illustration.

![enduser_assignment](enduser_assignment.png)

The below script will update the above PIM settings for the Contributor role on the target subscription. The subscription id output from the Bicep deployment will be used here to set the scope. Remember, the scope can also be management and resource groups.

Each Azure role has a unique policy id per subscription for PIM policy assignments. This must be retrieved using `Get-AzRoleManagementPolicyAssignment` and later be used when setting the new policy using `Update-AzRoleManagementPolicy`.

Each rule id (not to be confused with policy id) is constructed as its own rule and can later be bunched together in the **$AllRules** variable.

```powershell
Param (
    [CmdletBinding()]
  
    [parameter(Mandatory)]
    [string]$SubscriptionId
)

# Contributor role id in Azure
$RoleId = "b24988ac-6180-42a0-ab88-20f7382dd24c"

# Set scope for PIM settings and assignments
$Scope = "/subscriptions/$subscriptionId"

# Get unique policy id for $RoleId on target subscription
$GetPolicy = Get-AzRoleManagementPolicyAssignment -Scope $Scope | Where-Object { $_.Name -like "*$RoleId*" }
$PolicyId = ($GetPolicy.PolicyId -split "/")[6]

# Get the full roleDefinitionId for $RoleId for target subscription
$RoleDefinitionId = $GetPolicy.RoleDefinitionId

# Configure expiration for end users eligible assignments. I.e., Activation maximum duration in hours.
# maximumDuration = "PTxH" where x is the number of hours a user can have the role active. Max is 24.
$ExpirationRuleEndUser = [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Models.Api20201001Preview.RoleManagementPolicyExpirationRule]@{
    isExpirationRequired = "false";
    maximumDuration      = "PT12H";
    id                   = "Expiration_EndUser_Assignment";
    ruleType             = [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Support.RoleManagementPolicyRuleType]("RoleManagementPolicyExpirationRule");
    targetOperation      = @('All');
}

# Configure enablement rule for end users eligible assignments. I.e., prompt for Justification, MultiFactorAuthentication or Ticketing when enabling role.
$EnablementRuleEndUser = [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Models.Api20201001Preview.RoleManagementPolicyEnablementRule]@{
    enabledRule     = @('MultiFactorAuthentication','Justification');
    id              = "Enablement_EndUser_Assignment";
    ruleType        = [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Support.RoleManagementPolicyRuleType]("RoleManagementPolicyEnablementRule");
    targetOperation = @('All');
}

# Update settings for $RoleId on target subscription
$AllRules = [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Models.Api20201001Preview.IRoleManagementPolicyRule[]]@($ExpirationRuleEndUser, $EnablementRuleEndUser)
Update-AzRoleManagementPolicy -Scope $Scope -Name $PolicyId -Rule $AllRules
```

After running the script, we now allow eligible users to activate the Contributor role for 12 hours, force them to verify access using MFA and require a justification. This is perfect for Snack as they haven’t yet implemented MFA using Conditional Access rules. At least now it’s enforced in Azure.

![enduser_assignment_post](enduser_assignment_post.png)

### Admin user settings (Assignment blade in PIM)

To configure the next blade, we target the rule id’s of the admin settings.

![admin_assignment](admin_assignment.png)

Continuing with the previous parameters and variables, we want to allow permanent assignments and require MFA.

```powershell
# Configure expiration for admin eligible assignments. I.e., how long can a group or user be eligible for the role ('Allow permanent eligible assignment' and/or 'Expire eligible assignment after').
$ExpirationRuleAdminEligible = [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Models.Api20201001Preview.RoleManagementPolicyExpirationRule]@{
    isExpirationRequired = "false";
    maximumDuration      = "P365D";
    id                   = "Expiration_Admin_Eligibility";
    ruleType             = [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Support.RoleManagementPolicyRuleType]("RoleManagementPolicyExpirationRule");
    targetOperation      = @('All');
}

# Configure expiration for admin active assignment. I.e., how long can a group or user have an active assignment for the role ('Allow permanent active assignment' and/or 'Expire active assignment after').
$ExpirationRuleAdminActive = [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Models.Api20201001Preview.RoleManagementPolicyExpirationRule]@{
    isExpirationRequired = "false";
    maximumDuration      = "P365D";
    id                   = "Expiration_Admin_Assignment";
    ruleType             = [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Support.RoleManagementPolicyRuleType]("RoleManagementPolicyExpirationRule");
    targetOperation      = @('All');
}

# Configure enablement rule for admin active assignments. I.e., prompt for Justification or MultiFactorAuthentication.
$EnablementRuleAdmin = [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Models.Api20201001Preview.RoleManagementPolicyEnablementRule]@{
    enabledRule     = @('MultiFactorAuthentication', 'Justification');
    id              = "Enablement_Admin_Assignment";
    ruleType        = [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Support.RoleManagementPolicyRuleType]("RoleManagementPolicyEnablementRule");
    targetOperation = @('All');
}

# Update settings for $RoleId on target subscription
$AllRules = [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Models.Api20201001Preview.IRoleManagementPolicyRule[]]@($ExpirationRuleAdminEligible, $ExpirationRuleAdminActive, $EnablementRuleAdmin)

Update-AzRoleManagementPolicy -Scope $Scope -Name $PolicyId -Rule $AllRules
```

After running the script it looks like this.

![admin_assignment_post](admin_assignment_post.png)


## Configure PIM assignments

All PIM settings for the Contributor role have now been configured for the new subscription. Next, Snack always creates one Azure AD group to assign as eligible for the Contributor role.

To assign the group, the cmdlet `New-AzRoleEligibilityScheduleRequest` is used. It requires a new unique guid for the request.

```powershell
Param (
    [CmdletBinding()]
  
    [parameter(Mandatory)]
    [string]$SubscriptionId
)

# Set scope for PIM settings and assignments
$Scope = "/subscriptions/$SubscriptionId"

# Contributor role
$RoleId = "b24988ac-6180-42a0-ab88-20f7382dd24c"

# Get unique id for $RoleId for target subscription
$GetPolicy = Get-AzRoleManagementPolicyAssignment -Scope $Scope | Where-Object { $_.Name -like "*$RoleId*" }
$PolicyId = ($GetPolicy.policyId -split "/")[6]
$RoleDefinitionId = $GetPolicy.RoleDefinitionId

# Construct group name
$GroupPrefix = "AzPIM"
$SubscriptionName = (Get-AzSubscription -SubscriptionId $subscriptionId).Name
$RoleName = "Contributor"

$GroupName = "$($GroupPrefix)_$($SubscriptionName)_$($RoleName)" -Replace '\s', ''

# Create Azure AD group
$Group = New-AzADGroup -DisplayName $GroupName -MailNickname $GroupName

Start-Sleep 30

# Assign group the Contributor role on target subscription (scope)
$Guid = (New-Guid).Guid
$StartTime = Get-Date -Format o 
$AssignmentParams = @{
    Name                        = $Guid
    Scope                       = $Scope
    ExpirationType              = "NoExpiration"
    PrincipalId                 = $Group.Id
    RequestType                 = "AdminAssign"
    RoleDefinitionId            = $RoleDefinitionId
    ScheduleInfoStartDateTime   = $StartTime
}

New-AzRoleEligibilityScheduleRequest @AssignmentParams
```

Once done, the group is shown under assignments.

![pim-assignment](pim-assignment.png)

To summarize, Snack has created their very first Landing Zone by deploying a Bicep template using an Azure DevOps pipeline. Next, PIM settings were configured for the Contributor role on the new subscription, and a new Azure AD group was created and assigned the role. Now the payroll team can be added to the group to be able to elevate access to their new subscription.

# Conclusion

Hopefully the Snack narrative wasn’t over the top. The team I work in meet a lot of customers in this exact situation, where we help them split huge subscriptions in to a more streamlined way of working with Azure.
 
I previously used the Rest API to handle the same things with PIM, and that script was a huge mess. if you’re thinking of using anything of this, adding some logic and checks to the scripts may be a good idea.
 
Thanks for reading! Feel free to reach out at my socials.