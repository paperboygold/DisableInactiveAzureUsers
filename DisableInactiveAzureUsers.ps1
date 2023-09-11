<#
.SYNOPSIS
    This script disables user accounts in Azure AD that haven't logged in within the past 90 days.

.DESCRIPTION
    - The script connects to Azure AD and then the Microsoft Graph API.
    - It fetches all users from the tenant and checks their last login date.
    - It compares the last login date to the current date to calculate days of inactivity.
    - Accounts inactive for more than 90 days will be disabled.

.INSTRUCTIONS
    1. Ensure you have the required AzureAD and Microsoft Graph permissions to run this script.
    2. Update the '<Credential Name>' with the name of the Azure Automation credential.
    3. Fill in the '<tenant ID>' with your Azure tenant ID.
    4. Replace the '<object id>' with the Object ID of the Azure AD group whose members should be whitelisted.
    5. Add any users to the $userWhitelist array that you don't want to be disabled, even if inactive.
    6. Add any whitelisted mailbox accounts to the $mailboxWhitelist array.
    7. Ensure you have error handling and logging mechanisms in place if deploying in a production environment.
    8. For the first run, consider commenting out the 'Set-AzureADUser' line to simulate what accounts would be disabled without making changes.
    9. Always backup any script before making modifications and test in a non-production environment first.

.NOTES
    Ensure you're adhering to organizational policies and have the necessary permissions before running scripts that modify user accounts.
#>

# Connect to AzureAD
Connect-AzureAD

# Connection information for Graph API connection
## Create credentials on the Azure Automation account that uses an app registration's ID as the username and secret as the password.
$credential = Get-AutomationPSCredential -Name '<Credential Name>'
$clientID = $credential.UserName
## Find your Azure tenant ID and place it below
$tenantid = "<tenant ID>"
$clientSecret = $credential.GetNetworkCredential().Password

$ReqTokenBody = @{
    Grant_Type    = "client_credentials"
    Scope         = "https://graph.microsoft.com/.default"
    client_Id     = $clientID
    Client_Secret = $clientSecret
}

$TokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantid/oauth2/v2.0/token" -Method POST -Body $ReqTokenBody

# Get all users in the tenant
$uri = 'https://graph.microsoft.com/beta/users?$select=displayName,userPrincipalName,signInActivity'
$Today=(Get-Date)

$Data = while (-not [string]::IsNullOrEmpty($uri)) {
    $apiCall = Invoke-RestMethod -Headers @{Authorization = "Bearer $($Tokenresponse.access_token)"} -Uri $uri -Method Get
    $uri = $null
    if ($apiCall) {
        $uri = $apiCall.'@odata.nextLink'
        $apiCall
    }
}

$result = ($Data | Select-Object Value).Value
$Export = $result | Select-Object DisplayName,UserPrincipalName,@{n="LastLoginDate";e={$_.signInActivity.lastSignInDateTime}}
$Users = $Export | Select-Object DisplayName,UserPrincipalName,@{Name='LastLoginDate';Expression={[datetime]::Parse($_.LastLoginDate)}}

# Whitelist array based on provided users
$userWhitelist = @(
    "user.person@example.com"
)

$mailboxWhitelist = @(
    "dashboard@example.com"
)

# Fetch members of the Service Account Azure AD group using the group's Object ID
$groupObjectID = "<object id>"
$groupMembersUri = "https://graph.microsoft.com/v1.0/groups/$groupObjectID/members/microsoft.graph.user?$select=userPrincipalName"
$groupMembersAPI = Invoke-RestMethod -Headers @{Authorization = "Bearer $($Tokenresponse.access_token)"} -Uri $groupMembersUri

# Extract UserPrincipalNames of the group members
$groupUserPrincipalNames = $groupMembersAPI.value | ForEach-Object {$_.userPrincipalName}

# List to store group accounts that would have been disabled
$groupMembersToBeDisabled = @()

# List to store secondary whitelist (mailbox whitelist) accounts that would have been disabled
$mailboxAccountsToBeDisabled = @()

# List to store user whitelist accounts that would have been disabled
$userWhitelistAccountsToBeDisabled = @()

# List to store users which will be disabled.
$usersToBeDisabled = @()

Foreach ($User in $Users) {

    # Calculate inactivity days
    if ($User.LastLoginDate) {        
        $LastLogin = $User.LastLoginDate
        $TimeSpan = $Today - $LastLogin
        $TimeDays = $TimeSpan.Days
    } else {
        # Default inactivity period for users who have never logged in
        $TimeDays = 0
    }

    # Check for user whitelist accounts
    if ($userWhitelist -contains $User.userPrincipalName) {
        $userWhitelistAccountsToBeDisabled += [PSCustomObject]@{
            UserPrincipalName = $User.userPrincipalName
            DaysInactive      = $TimeDays
        }
        continue
    }

    if ($TimeDays -gt 90) {
        # Check for whitelisted group accounts
        if ($groupUserPrincipalNames -contains $User.userPrincipalName) {
            $groupMembersToBeDisabled += [PSCustomObject]@{
                UserPrincipalName = $User.userPrincipalName
                DaysInactive      = $TimeDays
            }
            continue
        }

        # Check for mailbox whitelist accounts
        if ($mailboxWhitelist -contains $User.userPrincipalName) {
            $mailboxAccountsToBeDisabled += [PSCustomObject]@{
                UserPrincipalName = $User.userPrincipalName
                DaysInactive      = $TimeDays
            }
            continue
        }

        # Accounts not in any whitelist or special group will be added to the list to be disabled
        $usersToBeDisabled += [PSCustomObject]@{
            UserPrincipalName = $User.userPrincipalName
            DaysInactive      = $TimeDays
        }
    }
}

# Disable the users that need to be disabled
Write-Host "`nDisabled accounts:"
foreach ($userDetails in $usersToBeDisabled) {
    Set-AzureADUser -ObjectId $userDetails.UserPrincipalName -AccountEnabled $false
    Write-Host "$($userDetails.UserPrincipalName) due to $($userDetails.DaysInactive) days of inactivity"
}

# Print user whitelist accounts that would have been disabled
if ($userWhitelistAccountsToBeDisabled.Count -gt 0) {
    Write-Host "`nUser whitelist accounts that would have been disabled due to inactivity:"
    $userWhitelistAccountsToBeDisabled | ForEach-Object {
        Write-Host "$($_.UserPrincipalName) - Inactive for $($_.DaysInactive) days."
    }
} else {
    Write-Host "`nNo user whitelist accounts found that would have been disabled due to inactivity."
}

# Print service accounts that would have been disabled
if ($groupMembersToBeDisabled.Count -gt 0) {
    Write-Host "`nService accounts that would have been disabled due to inactivity:"
    $groupMembersToBeDisabled | ForEach-Object {
        Write-Host "$($_.UserPrincipalName) - Inactive for $($_.DaysInactive) days."
    }
} else {
    Write-Host "`nNo service accounts found that would have been disabled due to inactivity."
}

# Print secondary whitelist (mailbox whitelist) accounts that would have been disabled
if ($mailboxAccountsToBeDisabled.Count -gt 0) {
    Write-Host "`nMailbox whitelist accounts that would have been disabled due to inactivity:"
    $mailboxAccountsToBeDisabled | ForEach-Object {
        Write-Host "$($_.UserPrincipalName) - Inactive for $($_.DaysInactive) days."
    }
} else {
    Write-Host "`nNo mailbox whitelist accounts found that would have been disabled due to inactivity. However, remember to review these accounts regularly!"
}