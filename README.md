# Azure AD Inactive User Disabler

This script disables user accounts in Azure AD that haven't logged in within the past 90 days.

## Description

- The script connects to Azure AD and then the Microsoft Graph API.
- It fetches all users from the tenant and checks their last login date.
- The script then compares the last login date to the current date to calculate days of inactivity.
- Accounts inactive for more than 90 days will be disabled.

## Instructions

1. Ensure you have the required AzureAD and Microsoft Graph permissions to run this script.
2. Update the '<Credential Name>' with the name of the Azure Automation credential.
3. Fill in the '<tenant ID>' with your Azure tenant ID.
4. Replace the '<object id>' with the Object ID of the Azure AD group whose members should be whitelisted.
5. Add any users to the `$userWhitelist` array that you don't want to be disabled, even if inactive.
6. Add any whitelisted mailbox accounts to the `$mailboxWhitelist` array.
7. Ensure you have error handling and logging mechanisms in place if deploying in a production environment.
8. For the first run, consider commenting out the `Set-AzureADUser` line to simulate what accounts would be disabled without making changes.
9. Always backup any script before making modifications and test in a non-production environment first.

## Notes

Ensure you're adhering to organizational policies and have the necessary permissions before running scripts that modify user accounts.

If you'd like to have more than one group whitelisted, review lines 72 to 81 in DisableInactiveAzureUsers.ps1 to see how you might add another group. You'll just need the group's object ID which can be found via the Azure portal.

## Script Functions

- Main script body: Connects to AzureAD, fetches token for Graph API, retrieves list of users, and checks their last sign-in activity.
- Whitelisting: Users can be whitelisted by adding them to `$userWhitelist` or `$mailboxWhitelist` arrays. Additionally, members of a specific Azure AD group can be whitelisted.
- Disabling users: After calculating inactivity days and checking against whitelists, the script disables users with inactivity of more than 90 days.