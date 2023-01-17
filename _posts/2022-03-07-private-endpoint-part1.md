---
layout: post
title: "What is this Private Endpoint, and where can I buy one? (Part 1)"
date: 2022-03-07 14:00:00 -0000
categories: [Private Endpoint]
img_path: /assets/img/2022-03-07-private-endpoint-part1/
---

That's a good question and something I'm going to try and answer in my first blog series. If you're like me you've probably browsed the Azure Security Center recommendations to get a better understanding of your secure score and what you can do to improve it, or maybe you have a server on-premises with no outbound internet connectivity that need access to a Storage Account blob in Azure.

This is where Private Endpoints can help. When you create a Private Endpoint for a supported PaaS service you are basically integrating the service with your virtual network, giving the service a private IP for other machines or services to communicate with. Take your finance Storage Account in Azure for example, you no longer have to connect to the blob containing your invoices over the internet, instead you will connect securely over your private network.

This blog series will be split in to two parts and focus on below scenario, where Azure is being used in a hybrid environment and there are domain controllers with DNS deployed both on-premises and in Azure.

![main](on-premises-forwarding-to-azure.png)

You can find more information here: \
[Azure Private Endpoint DNS configuration | Microsoft Docs](https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-dns)

# Configure DNS

For all this to work, DNS plays a big role and must also be properly configured in your environment. When you connect to your Storage Account blob in Azure, you must connect to the FQDN of the Storage Account, and not the private IP given to you by enabling Private Endpoint, or Azure will deny your request.

## Prepare the Azure environment

**Update: Please see my new Github repository that contains everything needed to deploy all zones and associated Azure policies.** \
[Hardstl/PrivateEndpoint (github.com)](https://github.com/Hardstl/PrivateEndpoint)

First we'll start by creating all the privatelink DNS zones. These are the zones where your A-records for the different Azure services where Private Endpoint is enabled will be created. Management of the privatelink DNS zones should be handled centrally by your IT or Azure team. Preferably you'll be creating all the privatelink DNS zones in a locked down subscription or resource group. In this example, the resource group is called central-dns-rg.

In the spirit of Azure, Bicep will be used to deploy all the zones. Don't flex your arms too hard now, that's not the bicep I'm referring to. Bicep is Microsoft replacement for ARM templates, and I highly suggest you check it out.

Once you have Bicep up and running, save the below code as dns.bicep – it will loop through all the zones in the parameter file and create them for you. If you don't feel comfortable with this, you can create the zones using the portal.

<script src="https://gist.github.com/Hardstl/c89c2e99ae42e9737e49bc9084ad4aaa.js"></script>

Save below code as dns.parameters.json in the same folder as the dns.bicep file.

<script src="https://gist.github.com/Hardstl/2f558a6afe33dea9c83b6943330c5a8c.js"></script>

Deploy your privatelink DNS zones by running New-AzResourceGroupDeployment and provide the Bicep and parameter file.

```powershell
New-AzResourceGroupDeployment -ResourceGroupName "central-dns-rg" -TemplateFile ".\dns.bicep" -TemplateParameterFile ".\dns.parameters.json"
```

Note: There are a few region based zones that are not in included in the list. \
privatelink.{region}.batch.azure.com \
privatelink.{region}.azmk8s.io \
privatelink.{region}.backup.windowsazure.com \
privatelink.{region}.hypervrecoverymanager.windowsazure.com

## Configure forwarder in Azure

For the client or server connecting to the Storage Account to properly resolve the public DNS name to the Private Endpoint, the request must relay on a DNS server that's placed in a virtual network that's connected to your hub. This can be done by having a domain controller in Azure where the forwarder is set to the Azure public DNS.

Go to your domain controllers DNS Manager in Azure and set the forwarder IP to 168.63.129.16.

![forwarder](azure-forwarder.png)

## Configure conditional forwarders on-premises

If you're running a hybrid environment where you also need to be able to resolve the Private Endpoint of your PaaS services from clients or servers on-premises, all the public DNS zones must be created as conditional forwarders in your on-premises domain controllers, pointing to your DNS relay servers in Azure.

To achieve this we can use something called DNS Partitioning. It helps us separate so that the Azure zones are only replicated to our on-premises domain controllers, and not to the ones in Azure that has the forwarder (168.63.129.16) configured.

To get started, run the below command on any domain controller, where Name can be anything descriptive. This will create the partition and register the server from where the command is ran from to the partition as a member.

```powershell
Add-DnsServerDirectoryPartition -Name "PrivateEndpoint"
```

<br>

We can now see the available partitions and if the server is a member (Enlisted).

![AddDnsServerDirectoryPartition](dnspartition-1.png)

<br>

If ran from a server that's not a member, it will show as Not-Enlisted.

![GetDnsServerDirectoryPartition](dnspartition-2.png)

<br>

To add another domain controller as a member, run the below command on the server.

```powershell
Register-DnsServerDirectoryPartition -Name "PrivateEndpoint"
```

<br>

You can also register a remote server by specifying -ComputerName <name> like:

```powershell
Register-DnsServerDirectoryPartition -Name "PrivateEndpoint" -ComputerName "srv-dc-02"
```

<br>

When adding a new conditional forwarder using the DNS manager, the PrivateEndpoint partition will show up as a new replication scope.

![DnsPartitionGui1](dnspartition-4.png)

Once added to the partition, the property of the zone will show a replication scope that says “All domain controllers in user-defined scope“.

![DnsPartitionGui2](dnspartition-3.png)

All the different public DNS forwarder zones can be found here or in below script. I recommend to start with one common service and test everything out before creating all the zones, for example blob storage or SQL.

<script src="https://gist.github.com/Hardstl/35dc1b8b1ebc147d1a988da9367382c5.js"></script>

It will look something like this once configured on-premises, where we point the zones to the domain controllers in Azure (ideally you'll have more than one).

![conditional-forwarders](conditional-forwarders.png)

## Configure vnet links for the privatelink DNS zones

The next step is to integrate the different privatelink DNS zones in Azure to your hub virtual network. In the below example I'm adding a vnet link for privatelink.blob.core.windows.net to my hub vnet. The domain controllers in Azure that are placed in the hub vnet will now be able to relay requests for this zone to the Azure DNS.

![vnetlink1](vnetlink1.png)

![vnetlink2](vnetlink2.png)

# Deploy Private Endpoint

It's time to deploy a Private Endpoint for a Storage Account named stapendtest001 in virtual network vnt-corevnet-noea-001, and also integrate it with the previously created zone privatelink.blob.core.windows.net. This will associate a NIC with the Storage Account and let me access it over my private network.

Before deploying the Private Endpoint, this is how nslookup resolves the public DNS name of the Storage Account.

![resolve-before](resolve-before.png)

To deploy the Private Endpoint, go to the Storage Account > Networking > Private endpoint connections and create a new one.