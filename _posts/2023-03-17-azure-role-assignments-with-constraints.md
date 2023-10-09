---
layout: post
title: "Azure Role Assignments with Constraints"
date: 2023-10-09 14:00:00 -0000
categories: [Governance]
tags: [Azure, RBAC, Governance]
img_path: /assets/img/2023-10-09-azure-role-assignments-with-constraints/
---

If you've worked in Azure, you have definitely come across managing access using Role Based Access Control (RBAC) and have been met with different challenges. Until recently, the RBAC model in Azure has been missing a key piece: the ability to enforce constraints on the delegation of role assignments. This missing piece has led to a less than ideal user experience for those managing Azure resources. Fortunately, Azure Role Assignments with Constraints is here, hopefully providing the missing piece to a complete RBAC model in Azure. With this new feature, IT administrators and stakeholders can now easily and securely manage access to Azure resources, greatly improving the experience for all parties.

## Role based access control

In most Azure environments I've worked in, IT rarely assigns **Owner** or **User Access Administrator** to stakeholders; instead, they're the gatekeepers for giving out permissions to resources. This often leads to tickets being placed with IT and long wait times for new stakeholders to start consuming services in Azure, and most often the actual teams have more knowledge of who should have access to a resource than IT has.

This will most likely lead to frustration as developers will have problems fully setting up an application or service. For example, a developer creates an Azure Function with a Managed Identity that requires **Storage Blob Data Contributor** to a Storage Account, but they're not able to assign any roles for that identity.

On the other hand, if given full permissions, someone inexperienced with Azure or someone who doesn't value security may end up exposing the environment to security risks. I think we can all agree the model isn't all there yet.

### How it works today

1. Alice assigns the User Access Administrator role to Dara for a subscription.
2. Dara can now assign any role to any user, group, or service principal at the subscription scope.

![rbac-today](rbac-today.png)

## Delegate role assignments with constraints

With this new feature, we can instead delegate Dara the ability to assign only certain roles and principal types. For example, we can allow Dara and their team members to assign only Service principals the **Key Vaults Secrets User** and **Storage Blob Data Contributor** roles. With this in place, the team is now able to create that Azure Function with a Managed Identity and assign it the **Storage Blob Data Contributor** for any resource inside that subscription.

### Constrains example

1. Alice assigns the Role Based Access Control Administrator role to Dara. Alice adds constraints so that Dara can only assign the Contributor or Reader roles to the Marketing and Sales groups.
2. Dara can now assign the Contributor or Reader roles to the Marketing and Sales groups.
3. If Dara attempts to assign other roles or assign any roles to different principals (such as a user or managed identity), the role assignment fails.

![arac-example](arac-example.png)

### Getting started

*Click the images to enlarge them*

To get started follow the below steps.

1. At your desired scope, go to the IAM blade and select **Add** to create a new role assignment.

    ![arac-add](arac-add.png)

2. Select the **Privileged administrator roles** tab and find the Role Based Access Control Administrator role.

    ![arac-add-2](arac-add-2.png)

3. Add the desired User or Group that should be able to delegate roles at the scope.

    ![arac-members](arac-members.png)

4. Select **Add condition** to define the conditions.

    ![arac-addcondition](arac-addcondition.png)

5. The portal will present three templates that can be used, and in this example I'm using the middle one. It will allow me to target what roles users in the **Az_Analytics_Users** group can assign, and to what identity types. Opening the advanced condition editor will present the full configuration experience that allows for finer tuning. For example, users can create role assignments, but not delete them.

    ![arac-types](arac-types.png)

6. I want them to be able to assign **Key Vaults Secrets User** and **Storage Blob Data Contributor** to **Service principals**.

    ![arac-addcondition-2](arac-addcondition-2.png)

7. Hit save and the configuration will be presented before assignment is made.

    ![arac-addcondition-3](arac-addcondition-3.png)

8. That's it! Users in the group **Az_Analytics_Users** are now able to assign the roles specified in the expression to Service principals. If they try to assign any other roles they'll be denied.

We can also configure everything using PowerShell.

```powershell
$condition = "
(
  (
    !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
  )
  OR 
  (
    @Request[Microsoft.Authorization/roleAssignments:PrincipalType] StringEqualsIgnoreCase 'ServicePrincipal'
    AND
    @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {ba92f5b4-2d11-453d-a403-e96b0029c9fe, 4633458b-17de-408a-b874-0445c86b69e6}
  )
)
"

$Params = @{
    roleDefinitionId = "f58310d9-a9f6-439a-9e8d-f62e7b41a168" # Role Based Access Control Administrator
    objectId = "f2358f05-6fac-4a84-ad43-0f17ae694d18" # My Azure AD group
    scope = "/subscriptions/3955eb45-74ab-49f6-ae3f-b35f6073ac8c" # My scope (/subscriptions/<sub-id>)
    conditionVersion = "2.0"
    condition = $condition
}

New-AzRoleAssignment @Params
```

### Another example

Here I'm using the advanced condition editor. Users are able to assign all roles except **Owner** and **User Access Administrator** for all principal types; users, group, and service principals. This is done by negating the expression by ticking the checkbox when configuring what roles can be assigned.

An imporant thing to note here is that when a user assigns a role to another user not already present in the tenant, a guest invitation will be sent out, unless guest invitation is restricted.

![rbac-ex2-expression](rbac-ex2-expression.png)

![rbac-ex2-expression2](rbac-ex2-expression2.png)

```powershell
$condition = "
(
  (
   !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
  )
  OR 
  (
    @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'User', 'ServicePrincipal', 'Group'}
    AND
    NOT @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {8e3af657-a8ff-443c-a75c-2fe8c4bcb635, 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9}
  )
)
"

$Params = @{
    roleDefinitionId = "f58310d9-a9f6-439a-9e8d-f62e7b41a168" # Role Based Access Control Administrator
    objectId = "f2358f05-6fac-4a84-ad43-0f17ae694d18" # My Azure AD group
    scope = "/subscriptions/3955eb45-74ab-49f6-ae3f-b35f6073ac8c" # My scope (/subscriptions/<sub-id>)
    conditionVersion = "2.0"
    condition = $condition
}

New-AzRoleAssignment @Params
```

## Final thoughts

I must say that I find this feature highly appealing, and I firmly believe that it will bring significant benefits to both IT administrators and developers alike. Previously, granting Owner or User Access Administrator permissions often entailed a considerable amount of responsibility for Azure stakeholders, akin to providing them with unrestricted access. However, with this new feature, we can now delegate some of the RBAC assignments to stakeholders, which will ultimately result in reduced wait times and minimize unwarranted frustration.
