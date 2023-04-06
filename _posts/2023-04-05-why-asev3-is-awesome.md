---
layout: post
title: "Why App Service Environment v3 is Awesome!"
date: 2023-04-05 14:00:00 -0000
categories: [Network]
tags: [Azure, Network]
img_path: /assets/img/2023-04-05-why-asev3-is-awesome/
---

The App Service Environment v3 has brought significant improvements to secure cloud computing. It offers a range of features that enhance the performance, security, and scalability of web applications. With this new version, developers and IT professionals can create and deploy secure web applications more efficiently without having to worry about infrastructure management.

What truly makes it awesome is how it integrates with virtual networks, providing applications with private inbound and outbound access without having to do any additional configuration on the App Services.

## What is App Service Environment v3

App Service Environment v3 provides a secure and isolated environment for hosting web applications. It's designed to offer enhanced scalability, security, and performance for applications that require high levels of isolation, network security, and regulatory compliance. It is built on top of Azure Virtual Network and offers features such as virtual IP addresses and custom domains.

It has full support for Network Security Groups and Route tables, making traffic management almost identical as running a VM on a virtual network.

The following services can be hosted:

- Windows and Linux web apps
- Docker containers (on web apps)
- Function apps
- Logic apps (Standard)

Older generations of App Service Environment were rather expensive. Now the cost of an empty ASEv3 is equal to the cost of one Windows I1v2 plan (Isolated v2), or around $400/month. Buying a reservation for a Windows I1v2 plan will save you almost 50%, and why shouldn't you buy a reservation?

## When should you use App Service Environment v3?

If you require private inbound and outbound connectivity for your deployed applications I would consider deploying an ASEv3. But, it's not always that simple as cost is a huge factor and smaller non-isolated app service plans are way cheaper. On the other hand, if private networking for apps is needed, Private Endpoints have to be deployed for each app, and VNet integration configured. The cost of a Private Endpoint is around $7 and can quickly add up for multiple apps. In an ASEv3, there's no need to create additional Private Endpoints for your apps!

A smaller sized solution consisting of a small set of apps with associated Private Endpoints and VNet integration won't really benefit from an ASEv3. The cost here is around $90/month.

![cost-s1plan](cost-s1plan.png)

A medium sized solution consisting of a few more apps that are all associated with Private Endpoints might benefit from an ASEv3. The cost here is around $190/month, which is still cheaper than the lowest priced Isolated V2 plan that costs around $220/month (with reservation). However, the benefit of not having to care about creating Private Endpoints and to VNet integrate all the apps will reduce a lot of complexity for your developers. Simply creating an app inside an Isolated plan and reaping all the benefits is a pretty nice thing to have.

The plans compared both have 2 Cores and 8 GB RAM.

![cost-pv3plan](cost-pv3plan.png)

If you're working with integrations you're most likely running a lot of Api, Function, and Web apps. This is a perfect candidate for an ASEv3. Let the infrastructure team handle the ASE instance, networking, and DNS. The dev team can now focus on setting up new integrations by deloying apps to the ASE and managing the APIs in the api management instance.

Don't forget to check out the new [workspaces](https://learn.microsoft.com/en-us/azure/api-management/workspaces-overview) feature for apim!

![cost-apimsolution](cost-apimsolution.png)

## Creating the ASEv3 instance

Deploying a new ASEv3 instance is rather straight forward. The deployment usually takes somewhere between 4-6 hours to complete. I'm going to create an internal ASEv3 that's only available from inside my virtual network, meaning any applications that should be available on the internet must be published using another service such as an Application Gateway.

1. Search for App Service Environment v3 in the marketplace to get started. On the Basics blade, select Internal or External and enter a name for the instance. The name must be globally unique and any applications deployed will be accessed using this name. For example, an App Service with the name **my-test-app-100** will be accessed by going to **my-test-app-100.hardstahl.appserviceenvironment.net**.
   ![new-ase-1](new-ase-1.png)

2. Dedicated hardware is most likely overkill for most scenarios. Zone redundancy sounds like something you'd want, but the base cost of the instance will then be the sum of **9 Windows I1v2 plans**.
   ![new-ase-2](new-ase-2.png)

3. The minimum subnet it can be deployed to is /27 and the recommended size is a /24. It has to be an empty subnet and be delegated to **Microsoft.Web/hostingEnvironments**. Selecting **Azure DNS Private Zone** will in this case create a zone in the resource group called **hardstahl.appserviceenvironment.net** and link it to the virtual network.
   ![new-ase-3](new-ase-3.png)

Once deployed, two resources are created. The ASEv3 instance will hold all your app service plans and apps, and the zone holds the DNS records needed to connect to apps.
![resources](resources.png)

An Azure blog post wouldn't be complete without a Bicep template!

<script src="https://gist.github.com/Hardstl/e0e2dabe4beccaab60c496d488e97240.js"></script>

## DNS configuration

For you to be able to connect to any apps, it must be done to the resource name followed by the DNS zone. The deployment will populate the zone with some DNS records pointing to the internal VIP address of the ASEv3 instance, which will be the first available IP in the subnet when selecting **Automatic** for the **Inbound IP address** part.

![dnsrecords](dnsrecords.png)

I'm also linking the zone to the virtual network where my Domain Controllers are joined to as I want to be able to connect from on-premises as well.

![vnetlinks](vnetlinks.png)

And on my on-premises Domain Controller I add a conditional forwarder for the zone pointing to my Domain Controller in Azure.

![conditional-forwarder](conditional-forwarder.png)

Once that is done I'm able to resolve the zone to the VIP address of the ASE from an on-premises PC.

![dnslookup](dnslookup.png)

## Deploying the first app

An App Service Plan is needed before any apps can be deployed. Create a normal plan from the marketplace and when picking the region, select the ASEv3 instance.

![new-plan](new-plan.png)

Create the app the same way, select the ASEv3 instance under region and then the plan.

![new-app](new-app.png)

The app is now reachable from inside my network, as long as port openings and routes are in place.

![access-app](access-app.png)

## Conclusion

Personally, I love how easy this service is to use, and how much it brings to the table.

The decision to implement an App Service Environment v3 is most often primarily influenced by financial considerations. A thorough financial analysis should take into account the size of App Service Plans, number of apps, and the quantity of Private Endpoints. However, it is crucial to also factor in the additional administrative expenses, team training pertaining to Private Endpoints, and consultant fees.