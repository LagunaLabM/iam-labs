# JML Lab 02 - Joiner provisioning
# Run after connecting to Microsoft Graph with the required delegated permissions.

# Read the HR CSV (this lab expects one employee per run)
$csvPath = Join-Path $PSScriptRoot "..\data\hr-new-hire.csv"
$newHires = @(Import-Csv -Path $csvPath -ErrorAction Stop)
if ($newHires.Count -ne 1) { throw "Joiner stopped: the HR CSV must contain exactly one employee." }
$newHire = $newHires[0]

# Validate required HR fields before making any changes in Entra ID.
$requiredFields = @(
    "EmployeeId",
    "FirstName",
    "LastName",
    "UserPrincipalName",
    "Department",
    "JobTitle",
    "UsageLocation",
    "ManagerUPN"
)
foreach ($field in $requiredFields) {
    if ([string]::IsNullOrWhiteSpace([string]$newHire.$field)) {
        throw "Joiner stopped: required CSV field '$field' is missing or empty."
    }
}

if ($newHire.Department -ne "Sales") {
    throw "Joiner stopped: this Joiner scenario expects Department = 'Sales'."
}

if ($newHire.UserPrincipalName -notmatch '^[^@\s]+@[^@\s]+$' -or
    $newHire.ManagerUPN -notmatch '^[^@\s]+@[^@\s]+$') {
    throw "Joiner stopped: UserPrincipalName and ManagerUPN must be valid UPN values."
}

# Pre-checks: employee, manager, license and Sales resources
$existingUser = Get-MgUser -Filter "userPrincipalName eq '$($newHire.UserPrincipalName)'" -ErrorAction Stop
if ($existingUser) { throw "Joiner stopped: this employee already exists in Entra ID." }

$manager = Get-MgUser -UserId $newHire.ManagerUPN -ErrorAction Stop

$p2Skus = @(Get-MgSubscribedSku -All -ErrorAction Stop | Where-Object SkuPartNumber -eq "AAD_PREMIUM_P2")
if ($p2Skus.Count -ne 1 -or $p2Skus[0].PrepaidUnits.Enabled -le $p2Skus[0].ConsumedUnits) {
    throw "Joiner stopped: no available Microsoft Entra ID P2 license was found."
}
$p2Sku = $p2Skus[0]

$salesGroups = @(Get-MgGroup -Filter "displayName eq 'JML-Dept-Sales'" -Property Id, DisplayName -ErrorAction Stop)
if ($salesGroups.Count -ne 1) { throw "Joiner stopped: expected exactly one JML-Dept-Sales group." }
$salesGroup = $salesGroups[0]

$salesPackages = @(Get-MgEntitlementManagementAccessPackage -Filter "displayName eq 'AP-Sales-Additional-Access'" -All -ErrorAction Stop)
if ($salesPackages.Count -ne 1) { throw "Joiner stopped: expected exactly one Sales Access Package." }
$salesPolicies = @(Get-MgEntitlementManagementAssignmentPolicy -Filter "accessPackage/id eq '$($salesPackages[0].Id)'" -All -ErrorAction Stop)
if ($salesPolicies.Count -ne 1) { throw "Joiner stopped: expected exactly one Sales assignment policy." }

# Create the employee account as disabled
$securePassword = $null
$password = $null
$passwordProfile = $null
try {
    $securePassword = Read-Host "Enter temporary password" -AsSecureString
    if ($null -eq $securePassword -or $securePassword.Length -eq 0) {
        throw "Joiner stopped: temporary password cannot be empty."
    }

    $password = [System.Net.NetworkCredential]::new("", $securePassword).Password
    $passwordProfile = @{ Password = $password; ForceChangePasswordNextSignIn = $true }

    $newUser = New-MgUser -DisplayName "$($newHire.FirstName) $($newHire.LastName)" `
        -UserPrincipalName $newHire.UserPrincipalName `
        -MailNickname $newHire.UserPrincipalName.Split("@")[0] `
        -AccountEnabled:$false -PasswordProfile $passwordProfile `
        -Department $newHire.Department -JobTitle $newHire.JobTitle `
        -UsageLocation $newHire.UsageLocation -EmployeeId $newHire.EmployeeId `
        -ErrorAction Stop
}
finally {
    $password = $null
    if ($null -ne $passwordProfile) { $passwordProfile.Clear() }
    if ($null -ne $securePassword) { $securePassword.Dispose() }
}
Write-Host "User created: $($newUser.UserPrincipalName)"

# Assign the manager and Microsoft Entra ID P2 license
Set-MgUserManagerByRef -UserId $newUser.Id `
    -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($manager.Id)" } `
    -ErrorAction Stop
Write-Host "Manager assigned: $($manager.DisplayName)"

Set-MgUserLicense -UserId $newUser.Id -AddLicenses @{ SkuId = $p2Sku.SkuId } -RemoveLicenses @() -ErrorAction Stop | Out-Null
Write-Host "Microsoft Entra ID P2 license assigned."

# Add the employee to the Sales department group
New-MgGroupMemberByRef -GroupId $salesGroup.Id `
    -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($newUser.Id)" } `
    -ErrorAction Stop | Out-Null
Write-Host "User added to department group: $($salesGroup.DisplayName)"

# Submit the Sales Access Package assignment request
$assignmentRequest = @{
    requestType = "adminAdd"
    assignment = @{
        targetId = $newUser.Id
        assignmentPolicyId = $salesPolicies[0].Id
        accessPackageId = $salesPackages[0].Id
    }
}

# Retry only the transient SubjectNotFound error caused by directory propagation delay.
# Do not retry other errors, as they may indicate a real configuration or permission problem.
$retryDelays = @(5, 10, 20, 30, 60, 120)
$salesRequest = $null

for ($attempt = 0; $attempt -le $retryDelays.Count; $attempt++) {
    try {
        $salesRequest = New-MgEntitlementManagementAssignmentRequest `
            -BodyParameter $assignmentRequest `
            -ErrorAction Stop
        break
    }
    catch {
        $errorText = @(
            $_.Exception.Message
            $_.ErrorDetails.Message
            $_.ToString()
        ) -join "`n"

        # Retry only when Entitlement Management has not resolved the newly created user yet.
        if ($errorText -notmatch "SubjectNotFound") { throw }

        # Stop after the initial attempt plus six retries (up to 245 seconds of waiting).
        if ($attempt -eq $retryDelays.Count) {
            throw "Joiner partially completed: Entitlement Management still returned SubjectNotFound after six retries. Do not rerun the full Joiner script; check the account and retry the Access Package assignment separately. Details: $errorText"
        }

        $delay = $retryDelays[$attempt]
        Write-Warning "Entitlement Management has not resolved the new user yet. Retrying in $delay seconds."
        Start-Sleep -Seconds $delay
    }
}

if ($null -eq $salesRequest) {
    throw "Joiner partially completed: no Access Package assignment request was created. Check the account before retrying this step."
}

Write-Host "Sales Access Package request submitted. Request ID: $($salesRequest.Id)"

# Wait for Entitlement Management to finish processing the request.
# A submitted/Accepted response means the request was accepted, not that access was delivered.
$pollIntervalSeconds = 15
$maxWaitMinutes = 10
$maxChecks = [int](($maxWaitMinutes * 60) / $pollIntervalSeconds) + 1
$assignmentStatus = $null

for ($check = 1; $check -le $maxChecks; $check++) {
    $assignmentStatus = Get-MgEntitlementManagementAssignmentRequest `
        -AccessPackageAssignmentRequestId $salesRequest.Id `
        -ErrorAction Stop

    # Stop successfully only when the complete package has been delivered.
    if ($assignmentStatus.State -eq "delivered") { break }

    # A partiallyDelivered request is not success; keep monitoring until delivery completes
    # or the maximum wait is reached. Failed, denied and canceled requests stop immediately.
    if ($assignmentStatus.State -in @("deliveryFailed", "denied", "canceled")) {
        throw "Joiner partially completed: Access Package request ended in state '$($assignmentStatus.State)' (status: '$($assignmentStatus.Status)'). Request ID: $($salesRequest.Id). The account remains disabled. Review the request in Entra ID."
    }

    if ($check -lt $maxChecks) {
        Write-Host "Access Package request state: $($assignmentStatus.State) (status: $($assignmentStatus.Status)). Checking again in $pollIntervalSeconds seconds ($check/$maxChecks)."
        Start-Sleep -Seconds $pollIntervalSeconds
    }
}

if ($assignmentStatus.State -ne "delivered") {
    throw "Joiner partially completed: Access Package was not confirmed as delivered within $maxWaitMinutes minutes. Current state: '$($assignmentStatus.State)' (status: '$($assignmentStatus.Status)'). Request ID: $($salesRequest.Id). The account remains disabled. Check the request before taking further action."
}

Write-Host "Sales Access Package delivered successfully. Status: $($assignmentStatus.Status)"
Write-Host "Joiner provisioning completed. The account remains disabled until manually enabled after verification."
