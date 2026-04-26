---
layout: post
title: "Corp vs Online"
date: 2026-04-26
categories: [PowerShell]
tags: [PowerShell, Network, Azure]
media_subpath: /assets/img/2026-04-26-corp-vs-online/
---

This post is my **interpretation** of what Azure Landing Zones and Corp vs. Online is after having done a bunch of ALZ implementations for customers of various sizes. I'm a big fan of structure and standardization which is exactly what ALZ brings, and it does so extremely well.

ALZ isn't:
- a copy-paste blueprint for your Azure platform. It is a reference architecture and starting point to build on. 
- one size fits all.

My interpretation of Azure Landing Zones is that it's both a technical framework and a way of working with Azure. I strongly believe we as infra people, are here to **enable** the rest of the organization to work in Azure with as little friction as possible while staying inside the guardrails we've put up.

Simplified, the technical framework is:
- a management group structure
- a set of policy initiatives and policies
- dedicated platform subscriptions
- subscription vending

![ManagementGroups](mg.png)

It's not RBAC assignments, logging, or hub networking. Even if those are part of the reference architecture, I don't think these have changed much with ALZ. A hub network has always been a hub network, RBAC assignments moved from resource group scopes in huge subscriptions to subscription scopes (or rg) in smaller app focused subscriptions, and logging is logging.

The other side is how we preferably work with Azure:
- one subscription per app (and environment if suitable)
- cost ownership tags directly on subscription
- budgets with thresholds and notifications on subscription
- Entra groups per subscription for access

Subscription vending is where ALZ becomes usable for the rest of the organization. The IT department should make it obvious how to request a landing zone, what parameters are required, how access is granted once it's provisioned, what rules apply, and which guardrails teams need to stay within. If there's too much friction here, at the start, we already lost.

## Corp vs. Online

Now this riddle has puzzled historians for decades, and it still isn't all that clear. But I want to give my view of what Corp vs. Online (Private vs Public) is.

**Corp** is where we deploy workloads that require private connectivity to other landing zones or on-premises. It can also be workloads that require maximum security but no outbound connectivity from the actual landing zone. Deploying a workload here shouldn't automatically give it access to other landing zones or on-premises as there should be a firewall in the hub.

**Online** is where we more freely can deploy workloads without the private network requirement. This doesn't make the workloads unsecure. You can still configure resource firewalls, VNets, service endpoints, and even private endpoints if you feel like it. You just won't have a pre-created VNet with a reserved IP address space and a peering to the hub.

Here's the thing though, both of these are valid places to host workloads that can be reached from the internet.

From a policy perspective, the only difference between Corp and Online is a few policies that are applied to Corp, but not Online. Let's focus on which policies matters for this post:

**Public network access should be disabled for PaaS services.** \
**Configure Azure PaaS services to use private DNS zones.**

If you're building a secure app with the need for on-premises access and say you have one workload in that stack that must be public for whatever reason, it's **totally acceptable to create a policy exemption**. That's what they're for. Document it and follow up from time to time. Depending on your network setup, you may still have hub firewall controls for egress and traffic toward on-premises or other landing zones.

I've seen discussions where it's suggested in these hybrid scenarios to move the app to Online and extend the **Configure Azure PaaS services to use private DNS zones** initiative there. I wouldn't recommend this for a few reasons:

- you're effectively forcing them to use the central privatelink zones, which creates a dependency on having a peering to the hub VNet and configured DNS servers.
- or you need to link the central privatelink zones to each Online landing zone VNet when they require it for their workload.

The policies assigned are guardrails, not the deciding factor for a whole stack. Instead of moving the workload to Online just to avoid a policy exemption, choose the path of least resistance.

In my usual vending model, Corp landing zones get a spoke VNet connected to the hub by default. Online landing zones don't. App teams can still deploy their own VNets, private endpoints, and privatelink zones in Online to secure their workloads, but those private endpoints should be local to that app.

Corp vs. Online is not about locking everything down as much as possible. It's about choosing the right access pattern for the workload. A common mistake is to treat Corp as "everything must be behind a private endpoint." It's usually the right choice, but it shouldn't be the default answer to every question.

## Private Endpoints and Developer Experience

Private Endpoints are great, but they're not free. The PE resource has a direct cost and then there's the bandwidth. A few function apps with their own storage accounts as an example. They also have an operational cost as DNS becomes more complex and troubleshooting becomes harder (tcpping is your friend).

Developers hate them! Maybe not hate, but it forces them to work in a way they're not comfortable with. Suddenly they need to think about firewall rules, routing, VPN access, private DNS zones, and whether their traffic actually resolves to the private IP. This is where we must work together and **enable** them. Friction and all that.

The biggest complaint I hear is developer access and developer experience. How do they access resources behind Private Endpoints? If teams are lucky, they're provided a VPN to use on their own PCs. But what about consultants, do they also qualify for VPN? Most of the time it's some AVD or VDI solution that's not optimized for developers; essential tools missing, no way to install what they need, slow machines.

This part is extremely important to have figured out before you start locking everything down in Corp. Happy workers, happy company?
