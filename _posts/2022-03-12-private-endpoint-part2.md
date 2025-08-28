---
layout: post
title: "What is this Private Endpoint, and where can I buy one? (Part 2)"
date: 2022-03-12 14:00:00 -0000
categories: [Private Endpoint]
tags: [Azure, Network, Private Endpoint]
media_subpath: /assets/img/2022-03-12-private-endpoint-part2/
---

In part 1 I gave an introduction on how to set up Private Endpoint and DNS and mentioned that the privatelink DNS zones should be handled centrally by your IT or Azure team. In this post I'll expand on how we can do just that by automating certain tasks, and how we should look at managing all of this.

Microsoft has put together a huge amount of information in their Cloud Adoption Framework and Github, and they'll use words such as Enterprise Scale and Landing Zones. If you're new to the CAF it can be rather overwhelming and I have found it best to read smaller parts at times when you're about to head down a path. For example, if you're about to set up Private Endpoints for the first time, google "private endpoints caf" or "private endpoints enterprise scale" and check it out.

![es-reference](es-reference.png)

You can find more information here: \
[Private Link and DNS integration at scale – Cloud Adoption Framework | Microsoft Docs](https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/private-link-and-dns-integration-at-scale)

# Management

If you're already following the Enterprise Scale model where you have everything neatly segmented in its own management groups and subscriptions it might look like something in the above picture. Here we have a Connectivity subscription (landing zone) containing your global network resources such as your hub vnet, vpn gateways and express route connections.

This subscription is most likely managed by your IT or Azure team, and they're the only ones allowed access. Logging is enabled for all resources and the subscription activity log is sent to a log analytics workspace and storage account in the management subscription.

This is also a perfect place to host your privatelink DNS zones seeing as none other than IT should be able to create or manage zones or records.

The reality though is that most organizations are not there yet, and that's totally fine. In the meantime the zones can be placed in any secured resource group.

> Tip: To view all your Private Endpoints, open the **Private Link Center** in Azure.

## Block creation of new privatelink DNS zones

To be able to centrally manage the zones and records, it's important that we block the creation of additional zones outside of the ones created and managed by IT. This can be done by creating a custom role when giving permissions to users, or better yet by applying an Azure Policy.

A common scenario when a user orders a new resource group is that they're given the Contributor role. Let's imagine that the user creates a Storage Account and wants to enable Private Endpoint (like we did in part 1). The user will be presented with the below choice where creating a new Private DNS zone is set as default. The user will most likely not think anything of it and just continue on and in the process create a duplicate zone where the DNS record will be registered.

![block-privatelink-zones](private-endpoint-newzone.png)

If we instead apply the below policy that will deny any creation of DNS zones with the prefix "privatelink.", the user won't be able to create any duplicate zones.

```json
{
  "description": "This policy restricts creation of private DNS zones with the `privatelink` prefix",
  "displayName": "Deny-PrivateDNSZone-PrivateLink",
  "mode": "All",
  "parameters": null,
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Network/privateDnsZones"
        },
        {
          "field": "name",
          "contains": "privatelink."
        }
      ]
    },
    "then": {
      "effect": "Deny"
    }
  }
}
```

The user will be blocked at the Review + create page when creating the Private Endpoint.

![private-endpoint-deny1](private-endpoint-deny1.png)

With details showing which policy denied the creation.

![private-endpoint-deny2](private-endpoint-deny2.png)

The goal here is to make the user press No to "Integrate with private DNS zone". Instead the integration and creation of the DNS record will be automated, which leads us to the next part.

# Automation

Like with anything IT related, automation helps a ton to reduce repetitive tasks, and creation of DNS records is just that. Azure Policy is a very powerful tool that can get this done. Luckily there are lots of policies compiled in the [Enterprise Scale Github](https://github.com/Azure/Enterprise-Scale) and their reference environments that require minimal effort to edit to fit the different PaaS services.

These policies will trigger a **deployIfNotExists** action when a Private Endpoint is created for the PaaS service, creating the A-record for the service in its privatelink DNS zone. There will be one policy per PaaS service that can be tied together in a policy initiative and then deployed to reduce the number of needed Managed Identities.

In this example I'm using a Storage Account named **stapendtest002** and the below policy is applied at the subscription level with **Network Contributor** permissions, targeting the **privatelink.blob.core.windows.net** zone.

![private-endpoint-blobpolicy](private-endpoint-blobpolicy.png)

```json
{
  "parameters": {
    "privateDnsZoneId": {
      "type": "String",
      "metadata": {
        "displayName": "privateDnsZoneId",
        "strongType": "Microsoft.Network/privateDnsZones"
      }
    },
    "effect": {
      "type": "String",
      "metadata": {
        "displayName": "Effect",
        "description": "Enable or disable the execution of the policy"
      },
      "allowedValues": [
        "DeployIfNotExists",
        "Disabled"
      ],
      "defaultValue": "DeployIfNotExists"
    }
  },
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Network/privateEndpoints"
        },
        {
          "count": {
            "field": "Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].groupIds[*]",
            "where": {
              "field": "Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].groupIds[*]",
              "equals": "blob"
            }
          },
          "greaterOrEquals": 1
        }
      ]
    },
    "then": {
      "effect": "[parameters('effect')]",
      "details": {
        "type": "Microsoft.Network/privateEndpoints/privateDnsZoneGroups",
        "roleDefinitionIds": [
          "/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
        ],
        "deployment": {
          "properties": {
            "mode": "Incremental",
            "template": {
              "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
              "contentVersion": "1.0.0.0",
              "parameters": {
                "privateDnsZoneId": {
                  "type": "String"
                },
                "privateEndpointName": {
                  "type": "String"
                },
                "location": {
                  "type": "String"
                }
              },
              "resources": [
                {
                  "name": "[concat(parameters('privateEndpointName'), '/deployedByPolicy')]",
                  "type": "Microsoft.Network/privateEndpoints/privateDnsZoneGroups",
                  "apiVersion": "2020-03-01",
                  "location": "[parameters('location')]",
                  "properties": {
                    "privateDnsZoneConfigs": [
                      {
                        "name": "storageBlob-privateDnsZone",
                        "properties": {
                          "privateDnsZoneId": "[parameters('privateDnsZoneId')]"
                        }
                      }
                    ]
                  }
                }
              ]
            },
            "parameters": {
              "privateDnsZoneId": {
                "value": "[parameters('privateDnsZoneId')]"
              },
              "privateEndpointName": {
                "value": "[field('name')]"
              },
              "location": {
                "value": "[field('location')]"
              }
            }
          }
        }
      }
    }
  }
}
```

When creating the Private Endpoint and making sure to select **No** at the integration part, the policy will kick in and deploy the **privateDnsZoneGroups** resource and register the DNS record.

![private-endpoint-blob](private-endpoint-blob.png)

It can take some time for the record to be created. If it doesn't show up the status of the **deployIfNotExists** operation can be viewed in the Activity log for the Private Endpoint resource for any errors. Once the operation has succeeded the DNS record for the Storage Account will be registered to the **privatelink.blob.core.windows.net** zone.

![private-endpoint-blob2](private-endpoint-blob2.png)

# Now give me all the other services!

**Update: Please see my new Github repository that contains everything needed to deploy all zones and associated Azure policies.** \
[Hardstl/PrivateEndpoint (github.com)](https://github.com/Hardstl/PrivateEndpoint)

As mentioned earlier, it's rather easy to edit the policy to fit the other PaaS services. Just change the **"Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].groupIds[*]"** equals value to the subresource matching the PaaS service, and the name of the config to something descriptive of that PaaS service.

All the subresources can be found [here](https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-overview#private-link-resource).

Changing the values to work for Key Vault would look something like this.

![private-endpoint-blob3](private-endpoint-blob3.png)

That’s all for this blog series. I hope it was useful!
