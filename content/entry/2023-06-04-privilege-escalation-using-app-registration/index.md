---
date: "2023-06-04"
title: Privilege escalation using Azure App Registration and Microsoft Graph
slug: privilege-escalation-azure-app-registration-microsoft-graph
description: Azure App Registrations are often used as system identities that have access to API's. Microsoft Graph is one of these API's that are often used and has application roles that are high privileged and can be abused by an attacker to escalate privileges.
tags:
- azure
- azure-active-directory
- microsoft-graph
- security
- app-registration
summary: Azure App Registrations are often used as system identities that have access to API's. Microsoft Graph is one of these API's that are often used and has application roles that are high privileged and can be abused by an attacker to escalate privileges.
---

> With great power comes great responsivility

A saying known from the Marvel movie Spider-man and very applicable to the power you have as an administrator of Azure Active Directory. As an Azure Active Directory administrator you have great responsibility to keep your Azure Active Directory in good health. One of those tasks is to maintain Azure Active Directory secure. For example by limiting the number of people that have priviled access, by enabling [Multi-Factory Authentication (MFA)](https://learn.microsoft.com/en-us/azure/active-directory/authentication/howto-mfa-getstarted), [Conditional Access](https://learn.microsoft.com/en-us/azure/active-directory/conditional-access/overview) or use [Privileged Idenitity Management](https://learn.microsoft.com/en-us/azure/active-directory/privileged-identity-management/pim-configure) for Just-In-Time privileged access. But also to maintain least privileged access for personal identities and system identities (App Registrations / Service Principals). In this blog post I'm going to dig into the latter!

Azure Active Directory knows two types of system identities: managed system identities and app registrations. For this blog post we're going to dig into the app registration from an attacker's perspective, or in other words, how can an app registration be abused to gain more access than the attacker is suppose to have.

## App Registration

An App Registration is a system identity that are often used by developers to enable the application to gain access to other applications using the OpenID Connect authentication mechanism. Gaining access to other applications is achieved by configuring API permissions which configure the scope of the access token retrieved by the application using the app registration. One of the available Microsoft APIs is Microsoft Graph, which gives access to Microsoft 365, Azure Active Directory, [and more](https://learn.microsoft.com/en-us/graph/overview). Each API has a set of application roles available that can be either configured for delegated access (gets access on behalf of an user) or for application access (gets access without an user). Configuring the API permission can be done by the owner of the App Registration, an Azure AD Application Administrator, or an identity that has permission to assign application roles to the specific app registration (or all). Configuring an API permission is always delegated or application, and always needs consent from either the user when delegated access has chosen, or by an Azure AD administrator for either delegated access or application access.

### Dangerous API permissions

Microsoft Graph has [a lot of application roles](https://learn.microsoft.com/en-us/graph/permissions-reference) including some dangerous (very) high privileged ones. The most high privileged application role on Microsoft Graph is the **AppRoleAssignment.ReadWrite.All** and **RoleManagement.ReadWrite.Directory**. This application role allows the user or application to grant additional privileges to itself and to other applicatios, The **AppRoleAssignment.ReadWrite.All** application role also includes the privilege **to grant admin consent**. With these permission you're able to assign other high privileged application roles, e.g.:
- **Directory.ReadWrite.All**: Allows the application to read and write data in your organizations Azure Active directory, including setting group memberships.
- **User.ReadWrite.All**: Allows the application to read and write the full profile of the user, including resetting passwords.
- **Group.ReadWrite.All**: Allows the application to read and write group properties, including setting group memberships.
- **Sites.ReadWrite.All**: Allows to read and write documents to all site collections.
- **Sites.FullControl.All**: Allows to have full control to sharepoint sites in all site collections.
- **Mail.Read**: Read all mailboxes 

### Privilege escalation using App Registration

Privilege escalation is gaining more privileges than the user is suppose to have. One of the options is to abuse API permissions that are authorized to an application using an app registration. Getting access to the app registration can be achieved by becoming the owner of the app registration or by getting (one of the) secrets. When access is gained, abuse of API permissions results in additional permissions that will help to get more higher privileges. For example:
- Grant additional roles to the application or (hijacked) accounts
- Grant additional API permissions
- Gain membership of highly privileged security groups (e.g. global administrator security group)
- Search for secrets (e.g. passwords) on sharepoint or in email
- Take over soneones identity to gain additional access

## Protect against privilege escalation

Now we know how app registrations can be abused to escalate privileges, I'll share some options to protect yourself against it.

### Don't do something stupid

It is a bit harsh, but don't do something stupid. Everyone makes mistakes now or then, and most times this is really not an issue, except when this mistake is made in (application) role assignments that grants access to highly privileged permissions! Try at all times to **not** assign **privileged roles** to any identity at all, unless you really need to. [The list of dangerous API permissions](#dangerous-api-permissions) gives you a few examples of privileged application roles that you need to be really carefull with. A good rule of thumb is to always use **least priviliged** roles and not not configure *any*.**ReadWrite**.**All** when you don't have to, also if this seems very useful for development purposes. Your Azure Active Directory (and other services) are **production**!

### Education

This is an open door, but often mistakes are made due to lack of education. In other words, people just don't know what they are doing. Identity and Access Management is becoming more and more important in a world that moves to public cloud platforms. Firewalls will not protect you in the public cloud, identities will! So keep them safe! One of the measurements to take is to lower the number of people that have access to give admin consent to dangerous API permissions.

### Policies to grant admin consent

With Azure Active Directory application consent policies you can create custom policies that include one or more "include" conditions and zero or more "exclude" conditions. The application consent policy can be configured very specific, e.g. to allow a user to admin consent a specific application role. These policies can be assigned to a custom directory role that can be used by personal accounts or applications. This allows the global administrator of the Azure Active Directory to disable the default admin consent policy and to use the custom policies instead. Since these custom policies only allow, or specificly deny dangerous permissions, you can prevent mistakes are made.

**Note:** The application consent policy is not available from the Azure Portal (yet) and should be configured using Powershell.

Read more about application consent policies in [my next blog post about application consent policies](https://www.pimwiddershoven.nl/entry/application-consent-policies-to-delegate-admin-consent/)!
**Sidenote:** This can also be used to automate granting admin consent without opening up the entire directory.

### Limit user consent

Most abuse in this blog post is about abusing application role assignment. However, abuse of delegated role assignments can also be destructive, e.g. you can steal an identity or do actions on behalf of someone else. By default, a user can consent to everything that doesn't need admin consent. For example, a user can consent to give read access to their mailbox. To reduce the risk of granting an application to access data it doesn't suppose to have access to, you can limit where a user can consent to.

Read more about user consent [on Microsoft Learn](https://learn.microsoft.com/en-us/azure/active-directory/manage-apps/configure-user-consent).

### Monitoring

Is it always possible that someone slips through. To get notified, configure alerts on dangerous actions. E.g. when a global administrators signs in or when privileged permissions are granted. It doesn't help to prevent the attacker to gain access, but you better get notified when things happen that you don't expect or want to double check.

I hope this blog post was helpfull. Stay safe!

**UPDATE:** Want to know how to prevent mistakes? [Read my blog post about application consent policies](https://www.pimwiddershoven.nl/entry/application-consent-policies-to-delegate-admin-consent/)!