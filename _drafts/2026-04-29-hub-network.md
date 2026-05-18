---
layout: post
title: "Hub Network"
date: 2026-04-29
categories: [Network]
tags: [Network, Azure]
media_subpath: /assets/img/2026-04-30-hub-networking/
---

User-defined routes. Routing. Complexity. Death by diagrams.

These are all things I try to avoid when setting up a hub network. Obviously we can't avoid routing, but we can try to avoid making it too complex. In Azure, a hub network should ideally contain only the core services required for connectivity and security, such as the VNet, Firewall, ER/VPN gateways, and Route Server. If we place things like Private DNS Resolvers, Application Gateways, Bastion, and other shared services in the hub, we increase routing complexity.

So the principle of this post is KISS: [Keep it simple, stupid!](https://en.wikipedia.org/wiki/Juicero)

## What are our options?

I'm going to list four viable options for building a hub network, ordered from most to least preferred. As with any blog post, this is just my opinion and not the only ways to build hub networks. Across all options, the main goal is to minimize dependency on user-defined routes.

In ALZ, when we provision a landing zone with a VNet to a team we also give them a custom role, for example Application Owner or Subscription Owner from the [ALZ repo](https://github.com/Azure/ALZ-Bicep/tree/main/infra-as-code/bicep/modules/customRoleDefinitions/definitions). In such a role, we don't allow them to edit any route tables for good reasons. What if we define routes such as 0.0.0.0 to our firewall and they simply remove it?

Some other questions around this:
- Do you allow teams to manage their own VNets?
- If so, can they create additional subnets without the requirement to attach a route table to it?
- Are they allowed to edit NSG rules?
- If you block teams from doing these, what's the process to request a new VNet, subnet, NSG rule, etc? Friction and all that (if you read my last post).

I'd genuinely like to hear how others are managing this.

### 1. Virtual WAN with Routing Intent

![VirtualWanRoutingIntent](vwan-routing-intent.png)
