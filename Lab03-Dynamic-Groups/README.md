# Lab03 - Dynamic Groups

## Objective

Demonstrate how Microsoft Entra Dynamic Groups automatically manage group membership based on user attributes.

## Scenario

The organization wants all users from the Sales department to be automatically added to a security group without requiring manual membership management.

A Dynamic Group is created using the Department attribute. Users whose Department is set to Sales are automatically included in the group. When a user's department changes, group membership is updated automatically.

## Technologies Used

* Microsoft Entra ID
* Dynamic Groups
* Dynamic Membership Rules
* User Attributes
* Security Groups

## Steps

### 1. Create Sales Users

Create two users with the Department attribute set to Sales.

![Create Sales User](images/01-create-sales-user.png)

![Create Sales User 2](images/01-create-sales-user_2.png)

### 2. Create an IT User

Create a user with the Department attribute set to IT.

![Create IT User](images/02-create-it-user.png)

### 3. Create a Dynamic Security Group

Create a new Security Group and configure the Membership type as Dynamic User.

![Create Dynamic Group](images/03-create-dynamic-group.png)

### 4. Configure the Dynamic Membership Rule

Configure a rule that automatically includes users whose Department attribute equals Sales.

Rule:

```text
(user.department -eq "Sales")
```

![Configure Membership Rule](images/04-configure-membership-rule.png)

### 5. Validate the Rule

Validate the rule to confirm that Sales users are included and non-Sales users are excluded.

![Rule Validation](images/05-rule-validation.png)

### 6. Verify Dynamic Group Membership

Verify that both Sales users are automatically added to the Dynamic Group.

![Dynamic Group Members](images/06-dynamic-group-members.png)

### 7. Change a User Attribute

Modify the Department attribute of one Sales user from Sales to Marketing.

![Change User Department](images/07-change-user-department.png)

### 8. Verify Automatic Membership Update

Confirm that the modified user is automatically removed from the Dynamic Group after the attribute change.

![Membership Updated After Attribute Change](images/08-membership-updated-after-attribute-change.png)

## Key Takeaways

* Dynamic Groups eliminate the need for manual membership management.
* Membership is determined by user attributes and dynamic rules.
* Changes to user attributes automatically trigger membership updates.
* Dynamic Groups help automate Identity and Access Management processes at scale.
