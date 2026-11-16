# Active Directory & Microsoft Entra ID Hybrid Identity Lab

A hands-on hybrid identity infrastructure lab built with Hyper-V and Microsoft Entra ID to practise Active Directory Domain Services (AD DS), DNS, directory synchronization with **Microsoft Entra Cloud Sync**, and **Microsoft Entra Hybrid Join**.

The environment consists of a Windows Server 2025 domain controller (`LAB-DC01`) and a Windows 11 Enterprise workstation (`LAB-WS01`) connected through an isolated Hyper-V network and integrated with a Microsoft Entra ID tenant (`hybridlab.onmicrosoft.com`). Configuration, troubleshooting, and validation tasks use Server Manager, the Microsoft Entra admin center, PowerShell, and Microsoft Graph.

## Lab Architecture

| Component | Configuration |
|---|---|
| Hypervisor | Hyper-V on Windows 11 Pro |
| Domain Controller (`LAB-DC01`) | Windows Server 2025 Standard Evaluation (Desktop Experience) + Entra Cloud Sync Agent |
| Client Workstation (`LAB-WS01`) | Windows 11 Enterprise Evaluation (26H2) — Domain-Joined & Entra Hybrid-Joined |
| Virtual Network | `LAB-AD` — Internal switch (`192.168.50.0/24`), with NAT (`192.168.50.1`) for outbound connectivity |
| Domain Controller IP | `192.168.50.10/24` |
| Client IP | `192.168.50.20/24` |
| On-Premises AD DS Domain | `corp.hybridlab.test` (NetBIOS: `CORP`) |
| Microsoft Entra Tenant | `hybridlab.onmicrosoft.com` |

## What This Lab Covers

- Hyper-V virtual machine and isolated NAT virtual network setup.
- Windows Server 2025 installation, AD DS / DNS role deployment, and forest promotion.
- DNS forwarders, SRV record validation, Windows Time (PDC Emulator), and `dcdiag` health checks.
- Windows 11 client network configuration, AD domain join, and secure channel validation.
- AD DS preparation for hybrid identity (KDS Root Key for gMSA, alternative UPN suffix, and scoped pilot OUs).
- Microsoft Entra Cloud Sync provisioning agent deployment and pilot user/group synchronization.
- Service Connection Point (SCP) registration, Device Sync (`AD2AADDeviceSync`), and **Microsoft Entra Hybrid Join** validation (`dsregcmd /status`).
- Real-world troubleshooting (execution policy blocks, missing `userCertificate`, agent quarantine, and OU scoping).

## Technical Documentation

The step-by-step implementation, PowerShell and Microsoft Graph commands, verification results, troubleshooting notes, and redacted screenshots are available in the [Technical Documentation](Documentation/README.md).

## Technologies

- Hyper-V
- Windows Server 2025 & Windows 11 Enterprise
- Active Directory Domain Services (AD DS) & DNS
- Microsoft Entra ID & Microsoft Entra Cloud Sync
- PowerShell & Microsoft Graph API (`dcdiag`, `nltest`, `dsregcmd`)

## Lab Scope

This is an isolated learning and portfolio environment intended for practice and demonstration. It is not a production design. The Windows operating systems were deployed using evaluation media, the `.test` domain is used only within this lab, and sensitive tenant/object identifiers have been redacted for security.