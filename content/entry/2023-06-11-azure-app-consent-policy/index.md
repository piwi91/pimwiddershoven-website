---
date: "2023-06-11"
title: Use application consent policies to delegate admin consent
slug: application-consent-policies-to-delegate-admin-consent
description: Application consent policies in Azure Active Directory can be used to delegate tenant-wide user and admin consent to other users, groups and applications. This blog post explains how to configure these policies using the Microsoft Graph REST API including a test case to show how a test user is able to grant admin consent to an application it owns.
tags:
- azure
- azure-active-directory
- microsoft-graph
- security
- consent
summary: Application consent policies in Azure Active Directory can be used to delegate tenant-wide user and admin consent to other users, groups and applications. This blog post explains how to configure these policies using the Microsoft Graph REST API including a test case to show how a test user is able to grant admin consent to an application it owns.
---

## Consent in Azure Active Directory

Consent is a process where users or administrator can grant permission for an application to access a protected resource, e.g. an API. Azure Active Directory has two types of consent: user consent and admin consent.

### User consent

A user can authorize an application to do actions on a protected resource on behalf of the user. These kind of permissions are known as "delegated permissions". User consent is initiated when a user signs into an application that requires a number of permissions on resources if those permissions are not already granted in an earlier session or by an administrator. The user is in control of the access granted to applications but only when user consent is allowed by the organization.

### Admin consent

An administrator can consent to permissions on behalf of all users or consent to direct access if there is no signed-in user. Admin consent is a privileged permission only available to privileged administrators, e.g. global adminstrators. When an admin grants consent on behalf of the organization, users won't get prompted for user consent anymore. An exception is when additional delegated permissions are required an administrator did not consent for.

Granting tenant-wide admin consent should only be given if you trust the application. Be careful with the level of privileges you consent too. Granting high privileged permissions opens up access to a large portion of organization's data or the permission to do privileged operations, e.g. role management, full access to Azure Active Directory, mailboxes, sites, or full user impersonation.

## Application consent policies

Application consent policies enables organization administrators to delegate consent permissions to users. It also includes a certain level of granularity in the number of permissions a user can consent for. An application consent policy consists of "include" and "exclude" rules that can be based on [classification](https://learn.microsoft.com/en-us/azure/active-directory/manage-apps/configure-permission-classifications?pivots=portal), permission type (application or delegated), resource application, permissions (e.g. application roles), client applications, client application tenants, client application publisher, and if you only allowed verified publishers or not. One to more include rules or zero to more exclude rules can be combined in a single policy which then can be assigned to the user consent workflow, or much more interesting, to custom roles that can be assigned to users.

## Configure application consent policies using Microsoft Graph API

Below I point out how to configure application consent policies using Azure CLI in Powershell, and how to use custom roles to allow users to consent to applications that are allowed by the policy.

### Pre-requisites

Because we'll use the Microsoft Graph REST API, only [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) is required. Login to your Azure Active Directory by running `az login` before proceeding. You need at least an Azure AD Premium 1 license on the directory to create custom roles.

A PowerShell module for Microsoft Graph and Azure AD are available as well, but be aware that these modules are not fully compatible across PowerShell versions (e.g. Azure AD doesn't run on PowerShell 7) and operating systems (e.g. Linux).

I'm running Azure CLI in PowerShell 7. Note that the examples below include escaping characters specifically for Powershell.

### Create application consent policy

Application consent policies in the Microsoft Graph REST API are called [permission grant policies](https://learn.microsoft.com/en-us/graph/api/resources/permissiongrantpolicy?view=graph-rest-1.0) and are part of the applications service principals API collection. A permission grant policy consists of a name, description and conditions. A application consent policy can be created using the example below.

```powershell
$params = @{
	id = "my-custom-consent-policy"
	displayName = "Custom application consent policy"
	description = "A custom permission grant policy to customize conditions for granting consent."
}
$result = az rest `
   --method POST `
   --uri 'https://graph.microsoft.com/v1.0/policies/permissionGrantPolicies' `
   --body (($params | ConvertTo-Json -Compress) -Replace '"', '\"')`
   --headers 'Content-Type=application/json' | convertfrom-json
```

In the example above the body parameters are added to a `$params` variable that is converted to JSON and escaped before it is passed to the `--body` parameter of the `az rest` command. The `POST` method will create a new permission grant policy as defined in the `$params` variable and will return a `201 Created` response code and a [permissionGrantPolicy](https://learn.microsoft.com/en-us/graph/api/resources/permissiongrantpolicy?view=graph-rest-1.0) object in the reponse body.

### Conditions

The application consent policy doesn't have any conditions yet. At least one include condition is required to be able to use it. I will add two conditions, one include condition and one exclude condition.

Both include and exclude conditions use the same [condition set object](https://learn.microsoft.com/en-us/graph/api/resources/permissiongrantconditionset?view=graph-rest-1.0) that has some parameters and default values:
- permissionType: can be either `delegated` or `application` (required)
- clientApplicationsFromVerifiedPublisherOnly: When set to `true` only application of verified publishers will be matched (default `false`)
- clientApplicationIds: a list of application IDs for client application to match or a list with the single value `all` (default `all`)
- clientApplicationPublisherIds = A list of Microsoft Partner Network IDs for verified publishers of the client application or a list with the single value `all` (default `all`)
- clientApplicationTenantIds = A list of Azure AD tenant IDs which the client application is registered or a list with the single value `all` (default `all`)
- permissionClassification = Permission classifications for permission being granted (e.g. `low`, `medium`, `high`) or `all` (default `all`)
- permissions = List of ID vaules for specific permissions to match with or a list with the single value `all` (default `all`)
- resourceApplication = Application ID of the resource application for which a permission is being granted or `any` to match all resources (default `any`)

I'm going to add an include condition first. The condition below will match delegated permissions for all verified applications.

```powershell
$params = @{
   permissionType = "delegated"
   clientApplicationsFromVerifiedPublisherOnly = $true
   clientApplicationIds = @("all") # default
   clientApplicationPublisherIds = @("all") # default
   clientApplicationTenantIds = @("all") # default
   permissionClassification = "all" # low, medium, high
   permissions = @("all") # default
   resourceApplication = "any" # default
}
$result = az rest `
   --method POST `
   --uri 'https://graph.microsoft.com/v1.0/policies/permissionGrantPolicies/my-custom-consent-policy/includes' `
   --body (($params | ConvertTo-Json -Compress) -Replace '"', '\"')`
   --headers 'Content-Type=application/json' | convertfrom-json 
```

Assume that you want to prevent Microsoft Graph is included. You can prevent this by adding an exclude condition specificly for a resource application as shown in the example below.

```powershell
$params = @{
   permissionType = "delegated"
   clientApplicationsFromVerifiedPublisherOnly = $false # default
   clientApplicationIds = @("all") # default
   clientApplicationPublisherIds = @("all") # default
   clientApplicationTenantIds = @("all") # default
   permissionClassification = "all" # low, medium, high
   permissions = @("all") # default
   resourceApplication = "00000003-0000-0000-c000-000000000000"
}
$result = az rest `
   --method POST `
   --uri 'https://graph.microsoft.com/v1.0/policies/permissionGrantPolicies/my-custom-consent-policy/excludes' `
   --body (($params | ConvertTo-Json -Compress) -Replace '"', '\"')`
   --headers 'Content-Type=application/json' | convertfrom-json 
```

### Add application consent policy to new custom role

The application consent policy is now ready to be assigned to a custom role. This role can be used to allow consent to all API permissions of client applications that are verified except for Microsoft Graph. I create a new Azure AD custom role and include the permission to consent for API permissions that match the policy we've created before. Application consent policies can either be assigned to grant permission to give user consent or admin consent, or both. In the example below both user consent and admin consent permissions are added to the custom role.

```powershell
$params = @{
	description = "Update basic properties of application registrations and allow consent using a custom consent policy."
	displayName = "Application Registration Support Administrator"
	rolePermissions = @(
		@{
			allowedResourceActions = @(
				"microsoft.directory/applications/basic/update"
            "microsoft.directory/applications/permissions/update"
            "microsoft.directory/servicePrincipals/managePermissionGrantsForSelf.my-custom-consent-policy" # user consent
				"microsoft.directory/servicePrincipals/managePermissionGrantsForAll.my-custom-consent-policy" # admin consent
			)
		}
	)
	isEnabled = $true
}
$role = az rest `
   --method POST `
   --uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions' `
   --body (($params | ConvertTo-Json -Compress -Depth 10) -Replace '"', '\"')`
   --headers 'Content-Type=application/json' | convertfrom-json 
```

Note that also the `microsoft.directory/applications/permissions/update` permission is added. It took me a while to figure out why the admin consent button was still greyed out but it all makes perfect sense. When giving consent on permissions you actually update the permission itself. To do this, you need to have the correct amount of privileges to update this.

### Assign custom role to an user

The new custom role 'Application Registration Support Administrator' is now created and available to be assigned to a principal. In the role assignment below, the custom role is assigned to a user on a tenant-wide scope. Be aware that `microsoft.directory/servicePrincipals/managePermissionGrantsForAll` grants a principal permission to give admin consent regardless of the chosen scope. The `microsoft.directory/applications/permissions/update` permission will honerate the scope so consenting is only possible when you have permissions to update the API permissions of the application.

```powershell
$user = az ad user show --id "user@tenant.onmicrosoft.com" | convertfrom-json 
$params = @{
	roleDefinitionId = $role.id
	principalId = $user.id
	directoryScopeId = "/"
}
$assignment = az rest `
   --method POST `
   --uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' `
   --body (($params | ConvertTo-Json -Compress) -Replace '"', '\"')`
   --headers 'Content-Type=application/json' | convertfrom-json
```

### How role assignments in Azure Active directory work

To understand a bit better how you can delegate consent permissions to other teams we need to dig deeper in how role assignments in Azure Active Directory actually work.

Role assignments have three parameters to configure:
- The role definition identifier, e.g. the custom role
- The principal identifier, e.g. a user
- The directory scope identifier, e.g. tenant-wide

The most important parameters are the principal identifier and directory scope identifier. The principal identifier is the identifier that gets the role assigned to. These can be users, but also role-assignable security groups and service principals including app registrations, managed identities, and other automation accounts. Together with the scope, which can be tenant-wide, an administrative unit, an application, or access package catalogs, this is very powerfull escpacially when you combine it with dynamic security groups and dynamic administrative units (which introduce their own additional risks, so be careful).

## Test case

For example, you want to allow a DevOps team to consent to API permissions (e.g. `User.Read.All`) of applications (e.g. `Microsoft Graph`) that are categorized as safe for their own created application. You are able to facilitate this with the following configuration:

1. Create a new application consent policy that includes a condition that only has the `User.Read.All` permission of the source application `Microsoft Graph`
2. Create a new custom role "DevOps Team Consent to safe API permissions"
3. Add the new application consent policy permission to this custom role **without** adding the permission to update application permissions
4. Assuming you have a role-assignable security group for this DevOps team (or just use a user as I will do) you assign the role to this principal with either a tenant-wide scope or for specific applications.

**Note:** I make the assumption the user is owner of the application, which will include the permission to update application permissions already! This will also work for service principals if you fully automate this.

Let's test a configuration that only allows consent for the `User.Read.All` permission from the `Microsoft Graph` application to an application a test user is an owner of. I have created two app registrations. The test user is only owner of one app registration. Both app registrations have already the `User.Read.All` permission but do not have admin consent.

**Note:** by default a `User.Read` delegated permission is added to the app registration. Remove this, otherwise the example below will not work because you don't have permission to consent for that API permission.

Before we start, we need to find the app ID and role ID. First we have to get the app ID of the `Microsoft Graph` application. Best way to find the application identifier for an application is by using Azure CLI and Powershell.
```powershell
$(az ad sp list --all | ConvertFrom-Json) | Where-Object { $_.displayName -match "Microsoft Graph" } | Select displayName, id, appId
```

When you got the app ID of the Microsoft Graph, query all the roles to get the role ID of the `User.Read.All` role.
```powershell
$sp = $(az ad sp show --id 00000003-0000-0000-c000-000000000000 | ConvertFrom-Json)
$sp.AppRoles | Select id, value, allowedMemberTypes
# Or filter on name
$sp.AppRoles | Where-Object { $_.value -match "User.Read.All" } | Select id, value, allowedMemberTypes
```

The script below configures everything we need to test admin consent delegated to a test user. First we create an application consent policy including condition and then we add a new custom role with least privileged permissions assigned to allow consent only by an application owner.

```powershell
# App consent policy
$params = @{
	id = "application-ms-graph-user-read-all"
	displayName = "Application Microsoft Graph User.Read.All"
	description = "A custom permission grant policy to allow consent on application Microsoft Graph User.Read.All."
}
$policy = az rest `
   --method POST `
   --uri 'https://graph.microsoft.com/v1.0/policies/permissionGrantPolicies' `
   --body (($params | ConvertTo-Json -Compress) -Replace '"', '\"')`
   --headers 'Content-Type=application/json' | convertfrom-json
# App consent policy include condition
$params = @{
    permissionType = "application"
    permissions = @("df021288-bdef-4463-88db-98f22de89214") # User.Read.All
    resourceApplication = "00000003-0000-0000-c000-000000000000" # Microsoft Graph App Id
}
$condition = az rest `
   --method POST `
   --uri "https://graph.microsoft.com/v1.0/policies/permissionGrantPolicies/$($policy.id)/includes" `
   --body (($params | ConvertTo-Json -Compress) -Replace '"', '\"')`
   --headers 'Content-Type=application/json' | convertfrom-json
# Custom role
$params = @{
   description = "Gives permission to grant consent to API permissions that are considered safe."
   displayName = "DevOps Team Consent to safe API permissions"
   rolePermissions = @(
      @{
         allowedResourceActions = @(
            "microsoft.directory/applications/allProperties/read"
            "microsoft.directory/servicePrincipals/allProperties/read"
            "microsoft.directory/servicePrincipals/managePermissionGrantsForSelf.$($policy.id)" # user consent
            "microsoft.directory/servicePrincipals/managePermissionGrantsForAll.$($policy.id)" # admin consent
         )
      }
   )
   isEnabled = $true
}
$role = az rest `
   --method POST `
   --uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions' `
   --body (($params | ConvertTo-Json -Compress -Depth 10) -Replace '"', '\"')`
   --headers 'Content-Type=application/json' | convertfrom-json
# Assign custom role to user
$user = az ad user show --id "test@mytenant.onmicrosoft.com" | convertfrom-json
$params = @{
	roleDefinitionId = $role.id
	principalId = $user.id
	directoryScopeId = "/"
}
$assignment = az rest `
   --method POST `
   --uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' `
   --body (($params | ConvertTo-Json -Compress) -Replace '"', '\"')`
   --headers 'Content-Type=application/json' | convertfrom-json
```

Now everything has been configured go into the Azure Portal and check if you can consent on one of the two app registrations created before.

The first app registration I have no ownership of and the "Grant admin consent" button is greyed out.

[![Screenshot of a not owned app registration that the user isn't able to admin consent](/files/2023-06-11-azure-app-consent-policy/test-no-owner-graph-permissions.png)](/files/2023-06-11-azure-app-consent-policy/test-no-owner-graph-permissions.png)

The second app registration I have ownership of but I accidentally added a second permission I don't have permission to consent, but the "Grant admin consent" button is available. Will it still grant consent?

[![Screenshot of an owned app registration that the user can grant consent but fails because of a permission that isn't allowed to consent to](/files/2023-06-11-azure-app-consent-policy/test-owner-graph-permissions-fail.png)](/files/2023-06-11-azure-app-consent-policy/test-owner-graph-permissions-fail.png)

No! Because I don't have permission to grant consent to `User.ReadWrite.All`, admin consent will fail. I first have to remove the permission I don't have permission to grant consent to and try again.

[![Screenshot of an owned app registration that the user can grant consent and succeeds](/files/2023-06-11-azure-app-consent-policy/test-owner-graph-permissions-success.png)](/files/2023-06-11-azure-app-consent-policy/test-owner-graph-permissions-success.png)

Which succeeds!

## Wrap up

We learned that application consent policies can be used to delegate user and admin consent to other principals and restrict to specific resources and permissions. The examples in this blog post can be used to setup a simple but effective policy to only allow admin consent for the `User.Read.All` role of the `Microsoft Graph` permission. It is pretty easy to change these examples that suit your own needs. At the time writing this blog post, you can't configure application consent policies throug the Azure Portal or new Microsoft Entra Portal and you need to use the REST API, Microsoft Graph PowerShell Library or Azure AD PowerShell Library.

I hope you found this post interesting. Leave your feedback in the comments below!