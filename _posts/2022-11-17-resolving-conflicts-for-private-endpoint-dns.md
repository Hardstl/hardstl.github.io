---
layout: post
title: "Resolving Conflicts for Private Endpoint DNS"
date: 2022-11-17 14:00:00 -0000
categories: [Private Endpoint]
tags: [Azure, Private Endpoint]
media_subpath: /assets/img/2022-11-17-resolving-conflicts-for-private-endpoint-dns/
---

Automating the process of creating Private Endpoint DNS configurations in their respective zones is key for a successful private networking implementation in Azure.

Record creation can be done using a set of Azure policies. However, not all of the built-in policies are able to deal with subresources of the same name being targeted to different zones. This may lead to records being created in the wrong zones.

This post will look at how we can solve this by adding another filter to the policies, and how we can manage subresources that require DNS records in multiple zones.

*Check out my [PrivateEndpoint repo](https://github.com/Hardstl/PrivateEndpoint) for a good start!*

# Subresources

All the subresources can be found [here](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns).

Looking through the list, it will become obvious that some subresources are mentioned multiple times, and need to be targeted to different privatelink zones.

For example, **Sql** can be found for Synapse Analytics and Cosmos DB.

![subresources_sql](subresources_sql.png)

**Account** for Cognitive Services and Purview.

![subresources_account](subresources_account.png)

**Namespace** for Event Hubs, Service Bus, and Relay. In this case it doesn’t matter though, as all are targeting the same privatelink zone.

![subresources_namespace](subresources_namespace.png)

# The Private Endpoint DNS policy

Looking at the typical policy that creates the DNS records, we can see that at row 22 the policy is only checking that:

Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].groupIds is equal to **Sql**.

This could mess with the creation of records, as depending on which policy hits the record will be created in that zone. The DNS record for your Synapse Analytics could be created in the Cosmos DB privatelink zone, and vice versa.

```json
{
  "parameters": {
    "privateDnsZoneId": {
      "type": "String",
      "metadata": {
        "displayName": "privateDnsZoneId",
        "strongType": "Microsoft.Network/privateDnsZones"
      }
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
              "equals": "Sql"
            }
          },
          "greaterOrEquals": 1
        }
      ]
    },
    "then": {
      "effect": "deployIfNotExists",
      "details": {
        "roleDefinitionIds": [
          "/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
        ],
        "type": "Microsoft.Network/privateEndpoints/privateDnsZoneGroups",
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
                  "location": "westeurope",
                  "properties": {
                    "privateDnsZoneConfigs": [
                      {
                        "name": "CosmosSql-privateDnsZone",
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

# The better Private Endpoint DNS policy

The solution is rather simple. In the policy, we need to specify the resource type when filtering the **privateLinkServiceConnections** property. Now this policy will only target Synapse Analytics Private Endpoints, and not be able to create records for types related to Cosmos DB.

This can be seen at rows 19-20 where the type has been added.

```json
{
  "parameters": {
    "privateDnsZoneId": {
      "type": "String",
      "metadata": {
        "displayName": "privateDnsZoneId",
        "strongType": "Microsoft.Network/privateDnsZones"
      }
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
          "field": "Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].privateLinkServiceId",
          "contains": "Microsoft.Synapse/workspaces"
        },
        {
          "count": {
            "field": "Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].groupIds[*]",
            "where": {
              "field": "Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].groupIds[*]",
              "equals": "Sql"
            }
          },
          "greaterOrEquals": 1
        }
      ]
    },
    "then": {
      "effect": "deployIfNotExists",
      "details": {
        "roleDefinitionIds": [
          "/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
        ],
        "type": "Microsoft.Network/privateEndpoints/privateDnsZoneGroups",
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
                  "location": "westeurope",
                  "properties": {
                    "privateDnsZoneConfigs": [
                      {
                        "name": "CosmosSql-privateDnsZone",
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

# Policy package repository

I have created a Github repo with some Bicep templates that will create all the policy definitions, and include them in a policy initiative. All definitions are created with the resource type filter.

The repo is updated when new services receive support for Private Endpoints, and everyone is free to contribute.

[Private Endpoint repo](https://github.com/Hardstl/PrivateEndpoint)

# Subresources with multiple zones

There’s currently no support in the repo for services that require the same subresource to be registered to multiple privatelink zones.

For this, we need to create all the **privateDnsZoneConfigs** in the **privateDnsZoneGroups** resource in the same policy. All the configs must be added using one array, as Private Endpoints don’t support multiple privateDnsZoneGroups.

Looking at the subresource list again, an example for this is **amlworkspace** that requires DNS records in two zones.

![azureml-zones](azureml-zones.png)

The below policy showcases how this can be done. Notice we now have 2 parameters and 2 privateDnsZoneConfigs as we have 2 zones. Other subresources may require more.

```json
{
  "parameters": {
    "privateDnsZoneIdApi": {
      "type": "String",
      "metadata": {
        "displayName": "privateDnsZoneIdApi",
        "strongType": "Microsoft.Network/privateDnsZones"
      }
    },
    "privateDnsZoneIdNotebook": {
      "type": "String",
      "metadata": {
        "displayName": "privateDnsZoneIdNotebook",
        "strongType": "Microsoft.Network/privateDnsZones"
      }
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
          "field": "Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].privateLinkServiceId",
          "contains": "Microsoft.MachineLearningServices/workspaces"
        },
        {
          "count": {
            "field": "Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].groupIds[*]",
            "where": {
              "field": "Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].groupIds[*]",
              "equals": "amlworkspace"
            }
          },
          "greaterOrEquals": 1
        }
      ]
    },
    "then": {
      "effect": "deployIfNotExists",
      "details": {
        "type": "Microsoft.Network/privateEndpoints/privateDnsZoneGroups",
        "roleDefinitionIds": [
          "/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
        ],
        "existenceCondition": {
          "allOf": [
            {
              "field": "Microsoft.Network/privateEndpoints/privateDnsZoneGroups/privateDnsZoneConfigs[*].privateDnsZoneId",
              "equals": "[parameters('privateDnsZoneIdApi')]"
            },
            {
              "field": "Microsoft.Network/privateEndpoints/privateDnsZoneGroups/privateDnsZoneConfigs[*].privateDnsZoneId",
              "equals": "[parameters('privateDnsZoneIdNotebook')]"
            }
          ]
        },
        "deployment": {
          "properties": {
            "mode": "incremental",
            "template": {
              "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
              "contentVersion": "1.0.0.0",
              "parameters": {
                "privateDnsZoneIdApi": {
                  "type": "String"
                },
                "privateDnsZoneIdNotebook": {
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
                        "name": "amlworkspaceApi-privateDnsZone",
                        "properties": {
                          "privateDnsZoneId": "[parameters('privateDnsZoneIdApi')]"
                        }
                      },
                      {
                        "name": "amlworkspaceNotebook-privateDnsZone",
                        "properties": {
                          "privateDnsZoneId": "[parameters('privateDnsZoneIdNotebook')]"
                        }
                      }
                    ]
                  }
                }
              ]
            },
            "parameters": {
              "privateDnsZoneIdApi": {
                "value": "[parameters('privateDnsZoneIdApi')]"
              },
              "privateDnsZoneIdNotebook": {
                "value": "[parameters('privateDnsZoneIdNotebook')]"
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

And the resulting configuration on the Private Endpoint from the policy.

![amlworkspace-records](amlworkspace-records.png)
