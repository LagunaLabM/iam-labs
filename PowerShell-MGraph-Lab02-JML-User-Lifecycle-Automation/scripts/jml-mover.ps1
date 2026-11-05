# JML Mover - Sales to Finance
# Grant and verify Finance access before removing Sales access.

$ErrorActionPreference = "Stop"

# Read the employee identifier from the same HR CSV used by Joiner.
$csvPath = Join-Path $PSScriptRoot "..\data\hr-new-hire.csv"
$hrRecords = @(Import-Csv -Path $csvPath -ErrorAction Stop)
if ($hrRecords.Count -ne 1 -or [string]::IsNullOrWhiteSpace($hrRecords[0].UserPrincipalName)) {
    throw "Mover stopped: the HR CSV must contain exactly one employee with a UserPrincipalName."
}
$employeeUPN = $hrRecords[0].UserPrincipalName

# Lab scenario settings.
$targetManagerUPN = "Finance.Manager@yourtenant.onmicrosoft.com" # Replace with your Finance Manager UPN.
$targetJobTitle = "Finance Analyst"
$sourceGroupName = "JML-Dept-Sales"
$targetGroupName = "JML-Dept-Finance"
$sourcePackageName = "AP-Sales-Additional-Access"
$targetPackageName = "AP-Finance-Additional-Access"
$activeStates = @("submitted", "pendingApproval", "delivering", "scheduled")

# Wait up to ten minutes for an Access Package request to finish.
function Wait-ForRequest {
    param([string]$RequestId)

    for ($attempt = 1; $attempt -le 120; $attempt++) {
        $request = Get-MgEntitlementManagementAssignmentRequest `
            -AccessPackageAssignmentRequestId $RequestId -ErrorAction Stop
        if ($request.State -eq "delivered") { return }
        if ($request.State -in @("deliveryFailed", "denied", "canceled", "partiallyDelivered")) {
            throw "Request $RequestId ended with state '$($request.State)'. Manual review is required."
        }
        Start-Sleep -Seconds 5
    }
    throw "Request $RequestId is still processing. Run the script again later; it checks for an existing request before creating another."
}

# Read the employee and the new manager. Allow reruns after the department has changed.
$employee = Get-MgUser -UserId $employeeUPN `
    -Property "id,displayName,userPrincipalName,department,jobTitle,accountEnabled" -ErrorAction Stop
if ($employee.Department -notin @("Sales", "Finance")) {
    throw "Mover stopped: expected Sales or Finance; found '$($employee.Department)'."
}
$manager = Get-MgUser -UserId $targetManagerUPN -Property "id,displayName" -ErrorAction Stop

# Find the department groups and Access Packages by name.
$sourceGroup = @(Get-MgGroup -Filter "displayName eq '$sourceGroupName'" -Property "id,displayName" -ErrorAction Stop)
$targetGroup = @(Get-MgGroup -Filter "displayName eq '$targetGroupName'" -Property "id,displayName" -ErrorAction Stop)
$sourcePackage = @(Get-MgEntitlementManagementAccessPackage -Filter "displayName eq '$sourcePackageName'" -All -ErrorAction Stop)
$targetPackage = @(Get-MgEntitlementManagementAccessPackage -Filter "displayName eq '$targetPackageName'" -All -ErrorAction Stop)
if ($sourceGroup.Count -ne 1 -or $targetGroup.Count -ne 1 -or $sourcePackage.Count -ne 1 -or $targetPackage.Count -ne 1) {
    throw "Mover stopped: a required Sales/Finance group or Access Package is missing or duplicated."
}
$sourceGroup = $sourceGroup[0]; $targetGroup = $targetGroup[0]
$sourcePackage = $sourcePackage[0]; $targetPackage = $targetPackage[0]

# Get the Finance assignment policy and current delivered assignments.
$targetPolicies = @(Get-MgEntitlementManagementAssignmentPolicy -Filter "accessPackage/id eq '$($targetPackage.Id)'" -All -ErrorAction Stop)
if ($targetPolicies.Count -ne 1) { throw "Mover stopped: expected exactly one Finance assignment policy." }
$targetPolicy = $targetPolicies[0]

$sourceAssignments = @(Get-MgEntitlementManagementAssignment `
    -Filter "accessPackage/id eq '$($sourcePackage.Id)' and state eq 'Delivered' and target/objectId eq '$($employee.Id)'" `
    -ExpandProperty target -All -ErrorAction Stop)
$targetAssignments = @(Get-MgEntitlementManagementAssignment `
    -Filter "accessPackage/id eq '$($targetPackage.Id)' and state eq 'Delivered' and target/objectId eq '$($employee.Id)'" `
    -ExpandProperty target -All -ErrorAction Stop)
if ($sourceAssignments.Count -gt 1 -or $targetAssignments.Count -gt 1) {
    throw "Mover stopped: multiple delivered assignments found. Manual review is required."
}

# Add Finance department membership if it does not already exist.
$targetMembers = @(Get-MgGroupMember -GroupId $targetGroup.Id -All -ErrorAction Stop |
    Where-Object { $_.Id -eq $employee.Id })
if ($targetMembers.Count -eq 0) {
    New-MgGroupMemberByRef -GroupId $targetGroup.Id -BodyParameter @{
        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($employee.Id)"
    } -ErrorAction Stop
    Write-Host "Added to Finance department group."
}
else { Write-Host "Finance department group membership already exists." }

# Ensure Finance Access Package is delivered. Reuse a pending request instead of creating a duplicate.
if ($targetAssignments.Count -eq 0) {
    $financeRequests = @(Get-MgEntitlementManagementAssignmentRequest `
        -Filter "accessPackage/id eq '$($targetPackage.Id)'" `
        -ExpandProperty 'assignment($expand=target)' -All -ErrorAction Stop |
        Where-Object { $_.RequestType -eq "adminAdd" -and $_.Assignment.Target.ObjectId -eq $employee.Id } |
        Sort-Object CreatedDateTime -Descending)
    $latestFinanceRequest = $financeRequests | Select-Object -First 1

    if ($latestFinanceRequest -and $latestFinanceRequest.State -in $activeStates) {
        $financeRequestId = $latestFinanceRequest.Id
        Write-Host "Resuming existing Finance request: $financeRequestId"
    }
    elseif ($latestFinanceRequest -and $latestFinanceRequest.State -eq "delivered") {
        $financeRequestId = $latestFinanceRequest.Id
        $targetAssignments = @(Get-MgEntitlementManagementAssignment `
            -Filter "accessPackage/id eq '$($targetPackage.Id)' and state eq 'Delivered' and target/objectId eq '$($employee.Id)'" `
            -ExpandProperty target -All -ErrorAction Stop)
        if ($targetAssignments.Count -ne 1) {
            throw "A previous Finance request is delivered, but its assignment is not visible. Check Entra before retrying."
        }
    }
    elseif ($latestFinanceRequest) {
        throw "Previous Finance request $($latestFinanceRequest.Id) ended with state '$($latestFinanceRequest.State)'. Review it before retrying."
    }
    else {
        $financeRequest = New-MgEntitlementManagementAssignmentRequest -BodyParameter @{
            requestType = "adminAdd"
            assignment = @{ targetId = $employee.Id; assignmentPolicyId = $targetPolicy.Id; accessPackageId = $targetPackage.Id }
        } -ErrorAction Stop
        $financeRequestId = $financeRequest.Id
        Write-Host "Finance Access Package request submitted: $financeRequestId"
    }

    Wait-ForRequest -RequestId $financeRequestId
    $targetAssignments = @(Get-MgEntitlementManagementAssignment `
        -Filter "accessPackage/id eq '$($targetPackage.Id)' and state eq 'Delivered' and target/objectId eq '$($employee.Id)'" `
        -ExpandProperty target -All -ErrorAction Stop)
    if ($targetAssignments.Count -ne 1) {
        throw "Finance request completed, but its delivered assignment could not be verified. Check Entra before continuing."
    }
}
Write-Host "Finance Access Package delivery verified."

# Update the employee's department, job title and manager after Finance access is ready.
if ($employee.Department -ne "Finance" -or $employee.JobTitle -ne $targetJobTitle) {
    Update-MgUser -UserId $employee.Id -Department "Finance" -JobTitle $targetJobTitle -ErrorAction Stop
}
Set-MgUserManagerByRef -UserId $employee.Id -BodyParameter @{
    "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($manager.Id)"
} -ErrorAction Stop
Write-Host "Employee details updated. Manager: $($manager.DisplayName)"

# Remove the Sales Access Package, reusing an existing removal request if one is pending.
if ($sourceAssignments.Count -eq 1) {
    $salesRequests = @(Get-MgEntitlementManagementAssignmentRequest `
        -Filter "accessPackage/id eq '$($sourcePackage.Id)'" `
        -ExpandProperty 'assignment($expand=target)' -All -ErrorAction Stop |
        Where-Object { $_.RequestType -eq "adminRemove" -and $_.Assignment.Id -eq $sourceAssignments[0].Id } |
        Sort-Object CreatedDateTime -Descending)
    $latestSalesRequest = $salesRequests | Select-Object -First 1

    if ($latestSalesRequest -and $latestSalesRequest.State -in $activeStates) {
        $salesRequestId = $latestSalesRequest.Id
        Write-Host "Resuming existing Sales removal request: $salesRequestId"
    }
    elseif ($latestSalesRequest -and $latestSalesRequest.State -in @("deliveryFailed", "denied", "canceled", "partiallyDelivered")) {
        throw "Previous Sales removal request $($latestSalesRequest.Id) ended with state '$($latestSalesRequest.State)'. Manual review is required."
    }
    elseif ($latestSalesRequest -and $latestSalesRequest.State -eq "delivered") {
        $salesRequestId = $latestSalesRequest.Id
        Write-Host "Sales removal request was already delivered: $salesRequestId"
    }
    elseif ($latestSalesRequest) {
        throw "Previous Sales removal request $($latestSalesRequest.Id) has state '$($latestSalesRequest.State)'. Manual review is required."
    }
    else {
        $salesRequest = New-MgEntitlementManagementAssignmentRequest -BodyParameter @{
            requestType = "adminRemove"
            assignment = @{ id = $sourceAssignments[0].Id }
        } -ErrorAction Stop
        $salesRequestId = $salesRequest.Id
        Write-Host "Sales Access Package removal submitted: $salesRequestId"
    }
    Wait-ForRequest -RequestId $salesRequestId
}

# Remove the old Sales department group membership if it still exists.
$sourceMembers = @(Get-MgGroupMember -GroupId $sourceGroup.Id -All -ErrorAction Stop |
    Where-Object { $_.Id -eq $employee.Id })
if ($sourceMembers.Count -gt 0) {
    Remove-MgGroupMemberByRef -GroupId $sourceGroup.Id -DirectoryObjectId $employee.Id -ErrorAction Stop
    Write-Host "Removed from Sales department group."
}
else { Write-Host "Sales department group membership already removed." }

# Verify that Sales access is gone and display the final employee state.
$remainingSalesAssignments = @(Get-MgEntitlementManagementAssignment `
    -Filter "accessPackage/id eq '$($sourcePackage.Id)' and state eq 'Delivered' and target/objectId eq '$($employee.Id)'" `
    -ExpandProperty target -All -ErrorAction Stop)
if ($remainingSalesAssignments.Count -gt 0) {
    throw "Mover incomplete: a delivered Sales Access Package assignment still exists."
}
$updatedEmployee = Get-MgUser -UserId $employee.Id `
    -Property "displayName,userPrincipalName,department,jobTitle,accountEnabled" -ErrorAction Stop

Write-Host ""
Write-Host "Mover completed for $($updatedEmployee.DisplayName)."
Write-Host "Department: $($updatedEmployee.Department)"
Write-Host "Job title: $($updatedEmployee.JobTitle)"
Write-Host "Account enabled: $($updatedEmployee.AccountEnabled)"
Write-Host "Finance Access Package: delivered"
Write-Host "Sales Access Package: removed"
