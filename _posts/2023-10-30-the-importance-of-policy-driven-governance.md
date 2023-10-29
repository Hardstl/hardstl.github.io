---
layout: post
title: "The Importance of Policy Driven Governance"
date: 2023-10-29 14:00:00 -0000
categories: [Governance]
tags: [Azure, Policy, Governance]
img_path: /assets/img/2023-10-30-the-importance-of-policy-driven-governance/
---

In Azure, following a policy-driven approach to governance is crucial. It's all about making sure that everyone who uses Azure can't set things up the wrong way. Imagine having a set of clear instructions that everyone must stick to, like a recipe for cooking. These policies are like those instructions, and they guarantee that all the services are set up securely and adhere to the company standards. They're there to prevent mistakes and make sure everything is in order, so that Azure stakeholders can't accidentally configure things the wrong way. It's like having a recipe for success in Azure.

In this post, I want to take you on a journey of a small application setup. It's a journey that leads us through the vast landscape of Azure services, but, much like a trail in need of some maintenance, we'll find that not all is as it should be.

But fear not, for we are not here to merely point out the flaws. We'll embark on a quest to uncover the issues and, more importantly, to discover how Azure Policy can come to the rescue, serving as our trusty guide in the journey to securing and optimizing this Azure landscape.

## (1) The Vulnerable Frontend

![trafficFlow-1](trafficFlow-1.png)

The application is published by an Application Gateway in Azure. An Application Gateway supports having a Web Application Firewall (WAF) policy assigned to the service or the individual configured sites (listeners). This is often missed when setting up the gateway, and makes all published sites vulnerable to attacks such as Cross-Site Scripting (XSS) and Sql Injection when not protected by the included OWASP rules.

A recommended approach would be to make sure the Application Gateway service has a WAF policy in prevention mode assigned to it. If a specific site in the gateway need to be in detection mode, assign a WAF policy to the listener and that will take presedence over the gateway policy.

There are a few built-in policies that could help ensure the Application Gateway is secured. Clicking the link will take you to the policy in the Azure portal.

The first policy will Deny the deployment of any gateway without a WAF policy assigned to it. \
[Web Application Firewall (WAF) should be enabled for Application Gateway](https://portal.azure.com/#view/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2F564feb30-bf6a-4854-b4bb-0d2d2d1e6c66)

The second policy will Deny the deployment of WAF policies not in the specified mode. \
[Web Application Firewall (WAF) should use the specified mode for Application Gateway](https://portal.azure.com/#view/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2F12430be1-6cc8-4527-a9a8-e3d38f250096)

## (2) The Deviating Azure SQL Server

![trafficFlow-2](trafficFlow-2.png)

The application connects to a public Azure SQL database. This is probabably the most used scenario today, and is not inherently wrong. If your company has decided on a private networking approach, the Azure SQL server should be placed on the company network behind a Private Endpoint. The idea of Private Endpoints is great, but I can almost guarantee that the concept is lost on the majority of Azure administrators and developers today.

To help everyone out there are a few built-in policies. Clicking the link will take you to the policy in the Azure portal.

This policy will Deny the deployment of an Azure SQL server if the `publicNetworkAccess` property is enabled, meaning the only way to connect is by creating a Private Endpoint. \
[Public network access on Azure SQL Database should be disabled](https://portal.azure.com/#view/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2F1b8ca024-1d5c-4dec-8995-b1a932b41780)

Searching the policy definitions in Azure for `to use private DNS zones` will show all built-in policies used to register DNS records for the Private Endpoints in the privatelink zones. For some reason there's no policy for Azure SQL server yet.

The Azure Landing Zones repository on [Github](https://github.com/Azure/Enterprise-Scale/wiki/ALZ-Policies#corp) bundles a lot of the necessary policies together in initatives for this specific purpose under the `Corp` management group scope.

## (3) The Exposed Company Data

![trafficFlow-3](trafficFlow-3.png)

A poorly configured storage account with `allowBlobPublicAccess` enabled could be a huge risk to your data, exposing it to the internet for anyone to see. The default choice when creating a container in a storage account is private access. However, it's an easy miss to make if you're not thinking clearly.

![newcontainer](newcontainer.png)

To disable `allowBlobPublicAccess` by default, this custom modify policy can be created that configures `allowBlobPublicAccess` to be disabled during resource creation or update. Whenever someone creates a new storage account or does a change to an existing one, it will be switched to disabled. If you need it to be enabled, create a policy exemption targeting the storage account.

```json
{
  "parameters": {
    "effect": {
      "type": "String",
      "metadata": {
        "displayName": "Effect",
        "description": "The effect determines what happens when the policy rule is evaluated to match"
      },
      "allowedValues": [
        "Modify",
        "Disabled"
      ],
      "defaultValue": "Modify"
    }
  },
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Storage/storageAccounts"
        },
        {
          "field": "Microsoft.Storage/storageAccounts/allowBlobPublicAccess",
          "notequals": false
        },
        {
          "not": {
            "allOf": [
              {
                "field": "id",
                "contains": "/resourceGroups/aro-"
              },
              {
                "anyOf": [
                  {
                    "field": "name",
                    "like": "cluster*"
                  },
                  {
                    "field": "name",
                    "like": "imageregistry*"
                  }
                ]
              }
            ]
          }
        }
      ]
    },
    "then": {
      "effect": "[parameters('effect')]",
      "details": {
        "roleDefinitionIds": [
          "/providers/microsoft.authorization/roleDefinitions/17d1049b-9a84-46fb-8f53-869881c3d3ab"
        ],
        "operations": [
          {
            "condition": "[greaterOrEquals(requestContext().apiVersion, '2019-04-01')]",
            "operation": "addOrReplace",
            "field": "Microsoft.Storage/storageAccounts/allowBlobPublicAccess",
            "value": false
          }
        ]
      }
    }
  }
}
```

Using the below query in the Azure Resource Graph Explorer will show any exposed storage accounts.

```
resources
| where type =~ 'Microsoft.Storage/storageAccounts'
| extend allowBlobPublicAccess = parse_json(properties).allowBlobPublicAccess
| project name, resourceGroup, subscriptionId, allowBlobPublicAccess
```

## (4) The Compromised Management VM

![trafficFlow-4](trafficFlow-4.png)

There's a management VM that developers are using by connecting to it via RDP. The spoke network is connected to the hub, giving it access to the company on-premises environment. A public IP has been assigned to the NIC of the VM, providing inbound access to the VM from the internet. The Network Security Group assigned to the Management subnet has an inbound rule allowing traffic from Any to Any over port TCP/3389. This is about as bad as it gets, but is a regular occurance.

![inbound-rdp](inbound-rdp.png)

Let's first deal with that public IP. This first policy is rather strict as it will deny the creation of any public IPs, meaning you'll most likely get a lot of requests when your stakeholders are trying to deploy various services that need a public IP and they're being denied.

```json
{
  "parameters": {
    "effect": {
      "type": "String",
      "allowedValues": [
        "Audit",
        "Deny",
        "Disabled"
      ],
      "defaultValue": "Deny",
      "metadata": {
        "displayName": "Effect",
        "description": "Enable or disable the execution of the policy"
      }
    }
  },
  "policyRule": {
    "if": {
      "field": "type",
      "equals": "Microsoft.Network/publicIPAddresses"
    },
    "then": {
      "effect": "[parameters('effect')]"
    }
  }
}
```

The second policy will instead deny when a network interface (NIC) is being associated with a public IP.

```json
{
  "parameters": {
    "effect": {
      "type": "String",
      "allowedValues": [
        "Audit",
        "Deny",
        "Disabled"
      ],
      "defaultValue": "Deny",
      "metadata": {
        "displayName": "Effect",
        "description": "Enable or disable the execution of the policy"
      }
    }
  },
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Network/networkInterfaces"
        },
        {
          "not": {
            "field": "Microsoft.Network/networkInterfaces/ipconfigurations[*].publicIpAddress.id",
            "notLike": "*"
          }
        }
      ]
    },
    "then": {
      "effect": "[parameters('effect')]"
    }
  }
}
```

Opening management traffic such as RDP and SSH from anywhere on the internet is something we should always refrain from doing. Using Microsoft Defender for Cloud and looking at the recommendation `Management ports should be closed on your virtual machines` you can easily see which VMs in your environment are vulnerable.

The following custom policy will deny the creation of any rules created with Any (*) or Internet as source if the destination port is 3389. You can still open RDP from the internet by specifying a public IP as source.

```json
{
  "parameters": {
    "effect": {
      "type": "String",
      "metadata": {
        "displayName": "Effect",
        "description": "Enable or disable the execution of the policy"
      },
      "allowedValues": [
        "Audit",
        "Deny",
        "Disabled"
      ],
      "defaultValue": "Deny"
    }
  },
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Network/networkSecurityGroups/securityRules"
        },
        {
          "allOf": [
            {
              "field": "Microsoft.Network/networkSecurityGroups/securityRules/access",
              "equals": "Allow"
            },
            {
              "field": "Microsoft.Network/networkSecurityGroups/securityRules/direction",
              "equals": "Inbound"
            },
            {
              "anyOf": [
                {
                  "field": "Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRange",
                  "equals": "*"
                },
                {
                  "field": "Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRange",
                  "equals": "3389"
                },
                {
                  "value": "[if(and(not(empty(field('Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRange'))), contains(field('Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRange'),'-')), and(lessOrEquals(int(first(split(field('Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRange'), '-'))),3389),greaterOrEquals(int(last(split(field('Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRange'), '-'))),3389)), 'false')]",
                  "equals": "true"
                },
                {
                  "count": {
                    "field": "Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRanges[*]",
                    "where": {
                      "value": "[if(and(not(empty(first(field('Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRanges[*]')))), contains(first(field('Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRanges[*]')),'-')), and(lessOrEquals(int(first(split(first(field('Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRanges[*]')), '-'))),3389),greaterOrEquals(int(last(split(first(field('Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRanges[*]')), '-'))),3389)) , 'false')]",
                      "equals": "true"
                    }
                  },
                  "greater": 0
                },
                {
                  "not": {
                    "field": "Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRanges[*]",
                    "notEquals": "*"
                  }
                },
                {
                  "not": {
                    "field": "Microsoft.Network/networkSecurityGroups/securityRules/destinationPortRanges[*]",
                    "notEquals": "3389"
                  }
                }
              ]
            },
            {
              "anyOf": [
                {
                  "field": "Microsoft.Network/networkSecurityGroups/securityRules/sourceAddressPrefix",
                  "equals": "*"
                },
                {
                  "field": "Microsoft.Network/networkSecurityGroups/securityRules/sourceAddressPrefix",
                  "equals": "Internet"
                },
                {
                  "not": {
                    "field": "Microsoft.Network/networkSecurityGroups/securityRules/sourceAddressPrefixes[*]",
                    "notEquals": "*"
                  }
                },
                {
                  "not": {
                    "field": "Microsoft.Network/networkSecurityGroups/securityRules/sourceAddressPrefixes[*]",
                    "notEquals": "Internet"
                  }
                }
              ]
            }
          ]
        }
      ]
    },
    "then": {
      "effect": "[parameters('effect')]"
    }
  }
}
```

## The Importance of Azure Policy

![trafficFlow-5](trafficFlow-5.png)

The journey is reaching its end, and I hope that through visualizing the different components and how easy it is to make configuration errors, the importance of having a policy driven governance in Azure is clear. I'd like to wrap things up with a final drawing showing how the setup could have been different were the policies in place to begin with.

1. There are now two Web Application Firewall policies assigned. One to the Application Gateway service in prevention mode and another to the site listener in prevention mode. Disabling any of the OWASP rules can now easily be done in the site listener policy, only affecting that site, leaving other newly created sites protected from the service policy.

2. The Azure SQL server has been placed in its own subnet by creating a Private Endpoint and attaching it to the server. By having the Private Endpoint there, we can now disable public network access.

3. The storage account no longer allows anonymous access to blobs. To get around this a policy exemption must be made by the central IT team with a justification for why it's needed. This resource could also be placed in the Private Endpoint subnet and have its public network access disabled completely.

4. The public IP has been removed from the VM, meaning all access must be done from inside the corporate network or VPN. This will greatly reduce the attack surface and the traffic can also be filtered in a firewall for more granular access.
