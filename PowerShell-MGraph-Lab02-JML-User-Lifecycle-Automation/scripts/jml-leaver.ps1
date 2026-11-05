# JML Leaver - Disable an employee account and remove lab-managed access.
# The user object is retained for audit purposes; it is not deleted.

$ErrorActionPreference = "Stop"

# Read the employee identifier from the same HR CSV used by Joiner and Mover.
$csvPath = Join-Path $PSScriptRoot "..\data\hr-new-hire.csv"
$hrRecords = @(Import-Csv -Path $csvPath -ErrorAction Stop)
if ($hrRecords.Count -ne 1 -or [string]::IsNullOrWhiteSpace($hrRecords[0].UserPrincipalName)) {
    throw "Leaver stopped: the HR CSV must contain exactly one employee with a UserPrincipalName."
}
$employeeUPN = $hrRecords[0].UserPrincipalName

# Resources managed by this lab.
$accessPackageNames = @(
    "AP-Sales-Additional-Access",
    "AP-Finance-Additional-Access"
)
$departmentGroupNames = @(
    "JML-Dept-Sales",
    "JML-Dept-Finance"
)

# Wait for an Access Package removal request to finish.
function Wait-ForAssignmentRequest {
    param([Parameter(Mandatory)][string]$RequestId)

    for ($attempt = 1; $attempt -le 120; $attempt++) {
        $request = Get-MgEntitlementManagementAssignmentRequest `
            -AccessPackageAssignmentRequestId $RequestId -ErrorAction Stop

        if ($request.State -eq "delivered") {
            return $request
        }

        if ($request.State -in @("deliveryFailed", "partiallyDelivered", "denied", "canceled") -or $request.Status -eq "Failed") {
            throw "Access Package removal failed. Request ID: $RequestId; state: $($request.State)."
        }

        Start-Sleep -Seconds 5
    }

    throw "Timed out waiting for Access Package removal. Request ID: $RequestId. Check its status before rerunning."
}

# Find the employee before making any changes.
$employee = Get-MgUser -UserId $employeeUPN `
    -Property "id,displayName,userPrincipalName,accountEnabled" -ErrorAction Stop

Write-Host "Processing leaver: $($employee.DisplayName)"

# Disable the account first to block new sign-ins.
if ($employee.AccountEnabled) {
    Update-MgUser -UserId $employee.Id -AccountEnabled:$false -ErrorAction Stop
    Write-Host "Employee account disabled."
}
else {
    Write-Host "Employee account is already disabled."
}

# Revoke refresh tokens and browser session cookies.
Revoke-MgUserSignInSession -UserId $employee.Id -ErrorAction Stop | Out-Null
Write-Host "Sign-in sessions revoked."

# Remove any delivered Sales or Finance Access Package assignments managed by this lab.
foreach ($packageName in $accessPackageNames) {
    $packages = @(Get-MgEntitlementManagementAccessPackage `
        -Filter "displayName eq '$packageName'" -All -ErrorAction Stop)

    if ($packages.Count -ne 1) {
        throw "Leaver stopped: expected exactly one Access Package named '$packageName'."
    }

    $package = $packages[0]
    $assignments = @(Get-MgEntitlementManagementAssignment `
        -Filter "accessPackage/id eq '$($package.Id)' and state eq 'Delivered' and target/objectId eq '$($employee.Id)'" `
        -ExpandProperty target -All -ErrorAction Stop)

    foreach ($assignment in $assignments) {
        # Reuse an existing removal request instead of submitting a duplicate.
        $removalRequests = @(Get-MgEntitlementManagementAssignmentRequest `
            -Filter "accessPackage/id eq '$($package.Id)'" `
            -ExpandProperty assignment -All -ErrorAction Stop |
            Where-Object { $_.RequestType -eq "adminRemove" -and $_.Assignment.Id -eq $assignment.Id } |
            Sort-Object CreatedDateTime -Descending)
        $latestRequest = $removalRequests | Select-Object -First 1

        if ($latestRequest -and $latestRequest.State -in @("submitted", "pendingApproval", "delivering", "scheduled")) {
            $requestId = $latestRequest.Id
            Write-Host "Resuming existing removal request for $packageName. Request ID: $requestId"
        }
        elseif ($latestRequest -and $latestRequest.State -eq "delivered") {
            Write-Host "Removal already delivered for $packageName."
            continue
        }
        elseif ($latestRequest) {
            throw "Previous removal request $($latestRequest.Id) ended with state '$($latestRequest.State)'. Manual review is required."
        }
        else {
            # Submit an administrative removal for this delivered assignment.
            $removalRequest = New-MgEntitlementManagementAssignmentRequest `
                -BodyParameter @{
                    requestType = "adminRemove"
                    assignment = @{ id = $assignment.Id }
                } -ErrorAction Stop
            $requestId = $removalRequest.Id
            Write-Host "Removal submitted for $packageName. Request ID: $requestId"
        }

        Wait-ForAssignmentRequest -RequestId $requestId | Out-Null
        Write-Host "Access Package removed: $packageName"
    }

    if ($assignments.Count -eq 0) {
        Write-Host "No delivered assignment found for $packageName."
    }
}

# Remove direct department-group memberships. Access Package resource groups
# are removed by Entitlement Management when their package assignments are removed.
foreach ($groupName in $departmentGroupNames) {
    $groups = @(Get-MgGroup -Filter "displayName eq '$groupName'" `
        -Property "id,displayName" -ErrorAction Stop)

    if ($groups.Count -ne 1) {
        throw "Leaver stopped: expected exactly one group named '$groupName'."
    }

    $group = $groups[0]
    $membership = @(Get-MgGroupMember -GroupId $group.Id -All -ErrorAction Stop |
        Where-Object { $_.Id -eq $employee.Id })

    if ($membership.Count -gt 0) {
        Remove-MgGroupMemberByRef -GroupId $group.Id `
            -DirectoryObjectId $employee.Id -ErrorAction Stop
        Write-Host "Removed from department group: $groupName"
    }
    else {
        Write-Host "No membership found in department group: $groupName"
    }
}

# Remove only the Microsoft Entra ID P2 license assigned by this lab.
$p2License = @(Get-MgUserLicenseDetail -UserId $employee.Id -All -ErrorAction Stop |
    Where-Object { $_.SkuPartNumber -eq "AAD_PREMIUM_P2" })

if ($p2License.Count -gt 0) {
    Set-MgUserLicense -UserId $employee.Id `
        -AddLicenses @() `
        -RemoveLicenses @($p2License[0].SkuId) `
        -ErrorAction Stop
    Write-Host "Microsoft Entra ID P2 license removed."
}
else {
    Write-Host "No Microsoft Entra ID P2 license assigned to this employee."
}

# Confirm that the account remains disabled.
$finalUser = Get-MgUser -UserId $employee.Id `
    -Property "displayName,userPrincipalName,accountEnabled" -ErrorAction Stop

if ($finalUser.AccountEnabled) {
    throw "Leaver incomplete: the employee account is still enabled."
}

Write-Host ""
Write-Host "Leaver completed for $($finalUser.DisplayName)."
Write-Host "Account enabled: $($finalUser.AccountEnabled)"
Write-Host "User object retained for audit purposes."
