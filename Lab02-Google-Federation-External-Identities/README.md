# Lab02 - Google Federation with Microsoft Entra External Identities

## Objective

Demonstrate how Microsoft Entra External Identities can federate authentication with Google using OAuth 2.0, allowing external users to authenticate with their Google accounts while Microsoft Entra maintains control over authorization.

## Scenario

An organization wants to allow external users with Google accounts to authenticate through Microsoft Entra External Identities.

To achieve this, Google is configured as an external Identity Provider (IdP) using OAuth 2.0 federation.

## Technologies Used

- Microsoft Entra ID
- Microsoft Entra External Identities
- Google Cloud Platform (GCP)
- Google Auth Platform
- OAuth 2.0

## Step 1 - Create a Google Cloud Project

A new Google Cloud project is created to host the OAuth configuration required for federation.

![Create Google Cloud Project](images/01-create-google-cloud-project.png)

## Step 2 - Configure OAuth Branding

The OAuth consent screen branding information is configured.

![Configure OAuth Branding](images/02-configure-oauth-branding.png)

## Step 3 - Configure the Audience

The application is configured as External so users outside the organization can authenticate.

![Configure Audience](images/03-configure-audience.png)

## Step 4 - Create the OAuth Client

An OAuth 2.0 client is created using the Web Application type.

![Create OAuth Client](images/04-create-oauth-client.png)

## Step 5 - Configure Redirect URIs

Authorized redirect URIs are configured to allow Google to return authentication responses to Microsoft Entra.

![Configure Redirect URIs](images/05-configure-redirect-uris.png)

## Step 6 - Generate Client Credentials

Google generates the Client ID and Client Secret required for federation.

![OAuth Client Created](images/06-oauth-client-created.png)

## Step 7 - Configure Google as an Identity Provider in Microsoft Entra

The Google OAuth credentials are configured in Microsoft Entra External Identities.

![Configure Google Identity Provider](images/07-configure-google-identity-provider.png)

## Step 8 - Verify the Federation Configuration

Google appears as a configured Identity Provider in Microsoft Entra.

![Google Identity Provider Enabled](images/08-google-identity-provider-enabled.png)

## Key Security Concepts Demonstrated

- Identity Federation
- External Identities
- OAuth 2.0
- Trust Relationships
- Authentication Delegation
- B2B Collaboration
- Identity Providers (IdP)
