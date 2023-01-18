---
layout: post
title: "Azure SQL Networking and the Lifecycle of Private Endpoints"
date: 2022-04-04 14:00:00 -0000
categories: [Private Endpoint]
tags: [Azure, SQL, Private Endpoint]
img_path: /assets/img/2022-04-04-azure-sql-private-endpoint/
---

Alright, so you’re thinking of enabling Private Endpoints for your Azure SQL server to increase your security posture and disable incoming connections from the internet. Maybe you’re hesitant because you don’t know if your applications or users will be able to connect once enabled.

In this post we’ll take a look at how we can manage connections to Azure SQL and what the lifecycle of a Private Endpoint looks like.

![sql-featureimage2](sql-featureimage2.png)

# Setup

| Resource | Type | Description |
| -------- | ---- | ----------- |
| LabstahlPC01 | Windows 10 client | Used to demonstrate connections using SSMS and Test-NetConnection |
| SRV-DC-01 | Domain Controller | Set up with forwarders to handle Private Endpoint connections |
| sql-privateendpoint-noea-test | Azure SQL | Azure SQL server accepting connections from the client, both over the internet and Private Endpoint |

# Connections

The Azure SQL connectivity architecture supports multiple scenarios, and you can read more about them here:

[Azure SQL Database connectivity architecture](https://docs.microsoft.com/en-us/azure/azure-sql/database/connectivity-architecture)

## Default

By default, all connections to Azure SQL are made over the internet. By adding your own public IP address in the rules list, you will be able to connect to the server.
 
The rules list can be found by going to your Azure SQL server and selecting the **Firewalls and virtual networks blade**.

![sqlfw-default](sqlfw-default.png)

`Test-NetConnection` is one of my favorite commands, it’s extremely useful. However, using it to test connections to Azure SQL can be misleading. It will always evaluate to True, even if your public IP hasn’t been added to the Azure SQL firewall, as long as you have line of sight to the server (no outgoing block in your own firewall).

![sql-private-tnc](sql-public-tnc.png)

If I try connecting to the server using SSMS, and I have the appropriate permissions on the server, I will be able to add my public IP directly from SSMS.

![sql-public-ssms](sql-public-ssms.png)

## Private Endpoint

If we instead add a Private Endpoint to the Azure SQL, we will connect securely over the private network. Check my [previous post](https://hardstl.github.io/posts/azure-sql-private-endpoint) to get started using Private Endpoints.

![sql-pe](sql-pe.png)

Attaching a Private Endpoint results in two new resources being created.

![sql-nic-pe](sql-nic-pe.png)

Running `Test-NetConnection` again shows that we resolve to the private IP of the NIC that has been attached to the Azure SQL server.

![sql-private-tnc](sql-private-tnc.png)

There’s no need to add any IP addresses to the Azure SQL firewall rules list. All connections are allowed, as long as you have line of sight in your internal network.

# Blocking Public Access

Enabling Private Endpoints doesn’t automatically disable public access to your server. Instead, the decision what path the connection will take is simply the response you get back when resolving the FQDN of the Azure SQL server.

Blocking public access is straight forward, we just tick the box **Deny public network access** and hit save.

![sql-block-publicaccess](sql-block-publicaccess.png)

Now all connections must be made over the Private Endpoint. Trying to connect using SSMS over the internet will now result in a deny.

![sql-block-message](sql-block-message.png)

Now this is the goal – we want to secure all access to our private network and disable any connections over the internet.

# Everyone is screaming, rollback now!

So you did your planning and got your change approved in the CAB and you implemented Private Endpoint for your Azure SQL server, it even worked on your computer. Cool, that’s a win in my book!

But now people are having issues connecting and screaming for a rollback. Luckily, it’s easy to get back to your previous state.

In this case, we start by enabling public access again by unticking **Deny public network access**.

![sql-enable-publicaccess](sql-enable-publicaccess.png)

Next, remove your Private Endpoint and NIC by deleting the resources in your resource group, or delete it from the Private Endpoint blade in your Azure SQL server. The latter will delete the association, but keep the resources.

![remove-sql-nic-pe](sql-nic-pe.png)

Either of the above delete methods will also make sure the A record is automatically deleted from the privatelink zone in Azure.

![sql-dns-record](sql-dns-record.png)

Once done, you’ll be able to connect to the public endpoint again just like before in no time. Seeing as the TTL record is 10 seconds, both your client/server and AD DNS will not hold the record for longer than 10 seconds.

After connecting over the Private Endpoint using a Windows client, this is how the local DNS cache looks like.

Type 1 = A \
Type 5 = CNAME

![client-dns-cache](client-dns-cache.png)

And AD DNS cache.

![ad-dns-cache](ad-dns-cache.png)

As you no longer have a Private Endpoint and connections are back to using internet, the AD DNS will instead cache the public IPs of Azure SQL.

![ad-dns-cachepublic](ad-dns-cachepublic.png)

# Conclusion

Thanks for reading. My socials are in left menu, feel free to reach out or follow! 🙂

- The cost of one Private Endpoint is roughly $7.30 per month, excluding data costs
- Test-NetConnection is unreliable, use it for testing access if you’re blocking tcp/1433 in your own firewalls
- Connections can be made over private or public network, even with Private Endpoint enabled
- If Deny public network access is enabled, all connections must be done over Private Endpoint
- The A record has a TTL value of 10 seconds, and is removed when removing the Private Endpoint