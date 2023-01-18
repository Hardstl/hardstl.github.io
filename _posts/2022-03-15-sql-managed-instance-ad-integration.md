---
layout: post
title: "SQL Managed Instance AD Integration"
date: 2022-03-15 14:00:00 -0000
categories: [SQL]
tags: [Azure, SQL]
img_path: /assets/img/2022-03-15-sql-managed-instance-ad-integration/
---

In this post we’ll talk about authenticating to SQL Managed Instance using Azure AD and Active Directory users and groups. If you’re running SQL server on-premises you most likely already have a standardized way of creating users and groups for your SQL servers and databases. These service accounts might be used in your different application connection strings, and AD groups for handling permissions such as db_datareader or db_datawriter.

In Azure SQL MI we create something called contained users at the database level and give them their appropriate permissions. A contained user can be both a user or group in Azure AD or on-premises AD. When the user has been provisioned, we can connect using a few different methods.

![containeduser-nobg](containeduser-nobg.png)

More information can be found here: \
[Azure Active Directory authentication – Azure SQL Database | Microsoft Docs](https://docs.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview)

# Authentication

There are a few different methods for signing in. We’ll explore the options more in detail below.

![ssms-methods](ssms-methods.png)

**SQL Server Authentication**
The standard SQL user method where a user is created directly on the SQL server or database.

**Azure Active Directory – Universal with MFA**
If the Azure AD or synchronized user is configured for MFA, the user must select Azure Universal Authentication to connect. Great for administrators. If the user account does not require MFA, the user can still use the other two Azure Active Directory Authentication options.

**Azure Active Directory – Password**
Supports Azure AD or synchronized users. The user connects using their userPrincipalName and password.

**Azure Active Directory – Integrated**
Supports federated or managed domain synchronized users using password hash or pass-through authentication. If you’re connecting from a domain joined machine, the user and device must be configured for seamless single sign-on through Azure AD Connect seeing as Kerberos is used here.
Setup

Below is a table of the setup that was used in this post.

Configure AD integration

Depending on which method of authentication you require, different configurations must be done. It’s almost as the complexity increases from top to bottom from the above list.

Let’s get started by getting the base things in place. First go to your Managed Instance and select Active Directory admin in the left pane. Grant the MI reader access to your Azure AD by pressing the red text.

Select Grant permissions. It requires a Global Administrator account.

Add an Azure Active Directory admin. This step is necessary to do before we start creating any contained users or groups in our MI. If this admin object is later deleted your previously added contained users will stop working and won’t be able to connect.

Select Set admin and pick a user or group from Azure AD. Hit Save once finished.

Add contained users and groups

When adding an Azure AD cloud only or AD synchronized user to a SQL MI, we create something called a contained user. The contained users are created at the database level, and they can be both a user or a group containing users. This can be done by logging in to the MI with an administrator account and running the below commands.

The base command to create a user, where external provider just means Azure AD.
CREATE USER “userPrincipalName” FROM EXTERNAL PROVIDER;

To create a group, replace userPrincipalName with the group displayName.
CREATE USER “displayName” FROM EXTERNAL PROVIDER;

/* Create contained user in database 'OmarComing' from Azure AD cloud only user jansson@netcloudone.se */
CREATE USER "jansson@netcloudone.se" FROM EXTERNAL PROVIDER;

/* Give user reader access to database 'OmarComing' */
ALTER ROLE db_datareader ADD MEMBER "jansson@netcloudone.se"


/* Create contained user in database 'OmarComing' from AD synchronized group 'DB-OmarComing-R' */
CREATE USER "DB-OmarComing-R" FROM EXTERNAL PROVIDER;

/* Give group reader access to database 'OmarComing' */
ALTER ROLE db_datareader ADD MEMBER "DB-OmarComing-R"

When running these commands the user or group will show up under the Database (OmarComing) > Security > Users.

If you’re getting an error saying the following you probably forgot to add an Azure Active Directory admin.

Principal ‘userPrincipalName’ could not be resolved. Error message: ‘AADSTS700016: Application with identifier ’00ef5ad8-581d-4d1d-b831-32d0801343a6’ was not found in the directory ‘FedAuthAzureSqlDb’. This can happen if the application has not been installed by the administrator of the tenant or consented to by any user in the tenant. You may have sent your authentication request to the wrong tenant.
Connections

Connections to SQL MI can be done over both a public and private endpoint, with a strong recommendation to disable the public endpoint and run all connections securely over the private endpoint.

When connecting to the private endpoint, TCP/1433 is used.
sqlmi-lab-01.184963e08585.database.windows.net, 1433

The public endpoint uses TCP/3342.
sqlmi-lab-01.public.184963e08585.database.windows.net, 3342

By default, the network security group that’s created during the deployment allows connections from the VirtualNetwork service tag to port TCP/1433. Allowing connections to the public endpoint over port TCP/3342 requires adding additional rules to the NSG.

Azure Active Directory – Password

Now that we’ve added a user and a group as contained users we can connect to the SQL MI and database using the different AD methods. Let’s explore the password method first.

Connection string
“Server=tcp:sqlmi-lab-01.184963e08585.database.windows.net;Initial Catalog=OmarComing;Persist Security Info=False;User ID=userPrincipalName;Password=userPassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Authentication=”Active Directory Password”;

Using SSMS
I’ll be connecting using the cloud only user ‘jansson@netcloudone.se’ that has db_datareader permissions on the database ‘OmarComing’.

I’ve also gotta press Options and make sure to enter the database I’m connecting to seeing as the contained user was created at the database level.

Azure Active Directory – Integrated

Clear text passwords in connection strings is cool and all. But integrated authentication is even cooler! The integrated authentication lets you connect to the SQL MI using an on-premises Active Directory user over the Kerberos protocol. This is all possible by configuring the seamless single sign-on feature of Azure AD Connect.

I suggest you give it a read here to make sure your environment meets the requirements.
Azure AD Connect: Seamless Single Sign-On – quickstart | Microsoft Docs

The status of the seamless SSO can be viewed under the Azure AD Connect blade of Azure AD.

Connection string
“Server=tcp:sqlmi-lab-01.184963e08585.database.windows.net;Initial Catalog=OmarComing;Persist Security Info=False;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Integrated”;

Using SSMS
To connect using the integrated authentication, I’m going to use a Windows 10 domain joined VM with signed in user ‘NETCLOUDONE\steve’. Just like the password method, I’m going to have to specify which database I’m connecting to as the permissions have been granted at the database level.

    Steve is an Active Directory user that’s synchronized to Azure AD
    DB-OmarComing-R is an Active Directory group that’s synchronized to Azure AD
    DB-OmarComing-R has been created as a contained user at the database level with role db_datareader
    Steve is a member of DB-OmarComing-R, giving him the db_datareader role

Troubleshooting
If you’re having issues connecting, verify that your seamless SSO is properly configured.

You might also be missing the necessary Azure Active Directory Authentication Library on your system that’s connecting to the SQL MI. The documentation on how to get these files installed on your system is a bit weird as it says you need to install SSMS, but I’m sure there must be some other way to get them.

C:\Windows\SysWOW64\adal.dll
C:\Windows\System32\adal.dll

This is the version I’ve been using by installing the latest version of SSMS.

Conditional Access MFA

If you have conditional access policies applied that enforces MFA for all cloud apps, you’ll probably experience problems connecting with the below error message.

What you can do is to exclude the enterprise application called ‘Azure SQL Database’ from the policy that enforces MFA. This in turn lowers your security, but you might not have a choice depending on how your application works and how you authenticate. You could probably design your CA policies a bit different, like excluding certain IP addresses where you’re connecting from.

The ‘Azure SQL Database’ application is tenant wide and covers all your Azure SQL databases and SQL Managed Instances.
Application ID: 022907d3-0f1b-48f7-badc-1ba6abab6d66

That’s all for this time. Thanks for reading!
