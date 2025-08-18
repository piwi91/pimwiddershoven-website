

Connect-MgGraph -Scopes "Policy.ReadWrite.PermissionGrant"

Connect-MgGraph -Scopes "Directory.ReadWrite.All"
az login

# List existing application consent policy
$result = az rest `
   --method GET `
   --uri 'https://graph.microsoft.com/v1.0/policies/permissionGrantPolicies' `
   --headers 'Content-Type=application/json' | convertfrom-json 
# Get existing application consent policy
$result = az rest `
   --method GET `
   --uri 'https://graph.microsoft.com/v1.0/policies/permissionGrantPolicies/my-custom-consent-policy' `
   --headers 'Content-Type=application/json' | convertfrom-json 
# Create application consent policy
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
# Delete application consent rule
az rest `
   --method DELETE `
   --uri 'https://graph.microsoft.com/v1.0/policies/permissionGrantPolicies/my-custom-consent-policy' `
   --headers 'Content-Type=application/json' | convertfrom-json 
# Add include conditions
$params = @{
	permissionType = "application"
   permissions = @("df021288-bdef-4463-88db-98f22de89214") # User.Read.All
   resourceApplication = "327ba63b-334e-4004-bb30-20a607de4098" # Microsoft Graph
}
$result = az rest `
   --method POST `
   --uri 'https://graph.microsoft.com/v1.0/policies/permissionGrantPolicies/my-custom-consent-policy/includes' `
   --body (($params | ConvertTo-Json -Compress) -Replace '"', '\"')`
   --headers 'Content-Type=application/json' | convertfrom-json 
# Add exclude conditions
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
# Create customer Azure AD role
$params = @{
   description = "Update basic properties of application registrations"
   displayName = "Application Registration Support Administrator"
   rolePermissions = @(
      @{
         allowedResourceActions = @(
            "microsoft.directory/applications/create",
            "microsoft.directory/servicePrincipals/allProperties/read",
            "microsoft.directory/servicePrincipals/create"
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
# Create customer Azure AD role
$params = @{
	description = "Update basic properties of application registrations"
	displayName = "Application Registration Support Administrator"
	rolePermissions = @(
		@{
			allowedResourceActions = @(
            "microsoft.directory/applications/create",
            "microsoft.directory/servicePrincipals/allProperties/read",
            "microsoft.directory/servicePrincipals/create"
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

# Update custom Azure AD role
$params = @{
	description = "Update basic properties of application registrations"
	displayName = "Application Registration Support Administrator"
	rolePermissions = @(
		@{
			allowedResourceActions = @(
            "microsoft.directory/applications/create"
            "microsoft.directory/applications/basic/read"
            "microsoft.directory/applications/permissions/update"
            "microsoft.directory/servicePrincipals/basic/read"
            "microsoft.directory/servicePrincipals/create"
            "microsoft.directory/servicePrincipals/managePermissionGrantsForSelf.my-custom-consent-policy" # user consent
				"microsoft.directory/servicePrincipals/managePermissionGrantsForAll.my-custom-consent-policy" # admin consent
			)
		}
	)
	isEnabled = $true
}
$role = az rest `
   --method PATCH `
   --uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions/ce675627-ba6f-4427-9220-658bc051e924' `
   --body (($params | ConvertTo-Json -Compress -Depth 10) -Replace '"', '\"')`
   --headers 'Content-Type=application/json' | convertfrom-json 
# Assign customer role to principal
$user = az ad user show --id "pim@pimwiddershoven.onmicrosoft.com" | convertfrom-json 
$params = @{
	"@odata.type" = "#microsoft.graph.unifiedRoleAssignment"
	roleDefinitionId = $role.id
	principalId = $user.id
	directoryScopeId = "/"
}
$assignment = az rest `
   --method POST `
   --uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' `
   --body (($params | ConvertTo-Json -Compress) -Replace '"', '\"')`
   --headers 'Content-Type=application/json' | convertfrom-json 
# Get role assignments for Azure AD role
$result = az rest `
   --method GET `
   --uri 'https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments' `
   --uri-parameters "{`"""filter`""": `"""roleDefinitionId eq '$($role.id)'`""", `"""expand`""": `"""principal`"""}" `
   --headers 'Content-Type=application/json' | convertfrom-json
# List role definitions
$result = az rest `
    --method GET `
    --uri 'https://graph.microsoft.com/beta/roleManagement/directory/roleDefinitions' `
    --uri-parameters "{`"""expand`""": `"""inheritsPermissionsFrom`"""}" `
    --headers 'Content-Type=application/json' | convertfrom-json

