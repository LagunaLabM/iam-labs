# ==========================================
# Lab09 - Bulk License Assignment
# Microsoft Graph PowerShell
# ==========================================

# -----------------------------
# 1. Connect to Microsoft Graph
# -----------------------------

Connect-MgGraph -Scopes "User.ReadWrite.All","Organization.Read.All"

# -----------------------------
# 2. Define Microsoft Entra ID P2 SKU
# -----------------------------

$skuId = "84a661c4-e949-4bd2-a560-ed7766fcaf2b"

# -----------------------------
# 3. Retrieve target users
# -----------------------------

$users = Get-MgUser -Filter "startsWith(userPrincipalName,'labuser')"

# -----------------------------
# 4. Assign Microsoft Entra ID P2 license
# -----------------------------

foreach ($user in $users) {

    Set-MgUserLicense `
        -UserId $user.Id `
        -AddLicenses @(
            @{
                SkuId = $skuId
            }
        ) `
        -RemoveLicenses @()

}

# -----------------------------
# 5. Verify license assignment
# -----------------------------

foreach ($user in $users) {

    Get-MgUserLicenseDetail -UserId $user.Id |
        Select-Object UserPrincipalName, SkuPartNumber

}
