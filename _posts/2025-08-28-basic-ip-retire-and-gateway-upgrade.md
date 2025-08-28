---
layout: post
title: "Basic IP Retire and Gateway Upgrade"
date: 2025-08-28 14:00:00
categories: [PowerShell]
tags: [PowerShell, Network, Azure]
media_subpath: /assets/img/2025-08-28-basic-ip-retire-and-gateway-upgrade/
---

Basic Public IPs in Azure will be [retired](https://azure.microsoft.com/en-us/updates?id=upgrade-to-standard-sku-public-ip-addresses-in-azure-by-30-september-2025-basic-sku-will-be-retired) on September 30, 2025. This means you'll have to upgrade to Standard SKU before the retirement date to prevent any service disruptions. From my experience, most customer environments include one or more Basic Public IPs that need to be managed, so I assume the majority of organizations with an Azure footprint do as well.

This post will explain how to find any Basic Public IPs and how to upgrade a VPN or ExpressRoute gateway that currently uses one.

## Identify Basic Public IPs

The [Service Retirement Workbook](https://portal.azure.com/#view/AppInsightsExtension/UsageNotebookBlade/ComponentId/Azure%20Advisor/ConfigurationId/community-Workbooks%2FAzure%20Advisor%2FAzureServiceRetirement/WorkbookTemplateName/Service%20Retirement%20(Preview)) is an amazing workbook that details all Azure services that are being retired.

You can also query the Resource Graph Explorer:

```
resources
| where type =~ "microsoft.network/publicipaddresses"
| where sku.name == "Basic"
```

## Extend Subnet

For us to be able to use the built-in [Gateway SKU Migration](https://learn.microsoft.com/en-us/azure/expressroute/gateway-migration) wizard to upgrade our ExpressRoute gateway, we need the GatewaySubnet where the gateway is deployed into to be of size /27 or larger. In our case the subnet size is /28, meaning we can't use the built-in wizard. Luckily for us, there's a [feature in preview](https://learn.microsoft.com/en-us/azure/virtual-network/how-to-multiple-prefixes-subnet?tabs=powershell) that lets us add additional address prefixes to a subnet.

![GatewaySubnet](gatewaysubnet.png)

Using PowerShell we can add an additional address prefix by running the below commands. I haven't experienced any downtime or issues by running the commands.

```powershell
$vnet = Get-AzVirtualNetwork -ResourceGroupName 'rg-con-sdc-prod-hub' -Name 'vnet-hub-sdc-prod'
Set-AzVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -VirtualNetwork $vnet -AddressPrefix '10.150.0.0/28', '10.150.32.0/27'
$vnet | Set-AzVirtualNetwork
Get-AzVirtualNetwork -ResourceGroupName 'rg-con-sdc-prod-hub' -Name 'vnet-hub-sdc-prod' | Get-AzVirtualNetworkSubnetConfig -Name 'GatewaySubnet' | ConvertTo-Json
```

In Bicep, there's a property called addressPrefixes:

```bicep
resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: 'vnet-hub-sdc-prod'
  location: 'swedencentral'
  properties: {
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefixes: [
            '10.150.0.0/28'
            '10.150.32.0/27'
          ]
        }
      }
    ]
  }
}
```

The additional prefix won't show in the portal UI under the subnet, but can be fetched using powershell or by viewing the virtual network JSON in the portal.

## Gateway Migration

Now the gateway migration is very straight forward using the wizard. You can find the full migration plan [here](https://learn.microsoft.com/en-us/azure/expressroute/expressroute-howto-gateway-migration-portal).

1. Go to the ExpressRoute Gateway in the portal and select **Gateway SKU Migration**.
2. Run **Validate** to check for any issues.
3. Run **Prepare** to deploy the new ExpressRoute Gateway and the managed Public IP - this may take up to an hour and can safely be ran prior to your service window.
4. During your service window, run **Migrate Traffic** after selecting the new gateway radio button - this takes around 5 minutes and may cause short downtime.
5. Test your changes before hitting commit!

## Conclusion

The new feature that lets us add multiple prefixes to subnets is such a great addition. Think about all those times you thought you sized a subnet just right, only to find out later it wasn’t big enough. Been there, done that!

The built-in Gateway SKU Migration is also super straightforward and will make life so much easier for customers.

That said, network changes this big should never be rushed. Always take the time to plan ahead, keep the business informed, and communicate properly.