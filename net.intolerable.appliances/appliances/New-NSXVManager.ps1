Function New-NSXVManager {
	<#
		.Synopsis
			Deploy a new NSX-V Manager virtual appliance

		.Description
			Deploys a NSX-V Manager from a specified OVA/OVF file. Today, this function only supports provisioning to IPv4 networks.

		.Parameter OVFPath
			Specifies the path to the OVF or OVA package that you want to deploy the appliance from.

		.Parameter Name
			Specifies a name for the imported appliance.

		.Parameter CLIPassword
			The password set for the default CLI (admin) user for the imported appliance. This value *must* be set at deployment.

		.Parameter CLIENPassword
			The password for CLI privilege (enable) mode for the imported appliance. If a value is not provided, the value in CLIPassword be used.

		.Parameter EnableSSH
			Specifies whether or not to enable SSH for remote access to the NSX-V Manager. Enabling SSH service is not recommended for security reasons.

		.Parameter EnableCEIP
			Specifies whether to enable VMware's Customer Experience Improvement Program ("CEIP"). The default will enable CEIP.

			VMware's Customer Experience Improvement Program ("CEIP") provides VMware with information that enables VMware to improve its products and services, to fix problems, and to advise you on how best to deploy and use our products.  As part of the CEIP, VMware collects technical information about your organization's use of VMware products and services on a regular basis in association with your organization's VMware license key(s). This information does not personally identify any individual. For additional information regarding the data collected through CEIP and the purposes for which it is used by VMware is set forth in the Trust & Assurance Center at http://www.vmware.com/trustvmware/ceip.html.

		.Parameter VMHost
			Specifies a host where you want to run the appliance.

		.Parameter InventoryLocation
			Specifies a datacenter or a virtual machine folder where you want to place the new appliance. This folder serves as a logical container for inventory organization. The Location parameter serves as a compute resource that powers the imported vApp.

		.Parameter Location
			Specifies a vSphere inventory container where you want to import the deployed appliance. It must be a vApp, a resource pool, or a cluster.

		.Parameter Datastore
			Specifies a datastore or a datastore cluster where you want to store the imported appliance.

		.Parameter DiskFormat
			Specifies the storage format for the disks of the imported appliance. By default, the storage format is thick. When you set this parameter, you set the storage format for all virtual machine disks in the OVF package. This parameter accepts Thin, Thick, and EagerZeroedThick values. The default option will be Thin.

		.Parameter Network
			The name of the virtual portgroup to place the imported appliance. The portgroup can be either a standard or distributed virtual portgroup.

		.Parameter IPAddress
			The IP address for the imported appliance.

		.Parameter SubnetMask
			The netmask or prefix for the imported appliance. The default value, if left blank, will be "255.255.255.0"

		.Parameter Gateway
			The default gateway address for the imported appliance. If a value is not provided, and the subnet mask is a standard Class C address, the default gateway value will be configured as x.x.x.1 of the provided network.

		.Parameter DNSServers
			The domain name servers for the imported appliance. Leave blank if DHCP is desired. WARNING: Do not specify more than two DNS entries or no DNS entries will be configured!

		.Parameter Domain
			The domain name server domain for the imported appliance. Note this option only works if DNS is specified above.

		.Parameter FQDN
			The hostname or the fully qualified domain name for the deployed appliance.

		.Parameter ValidateDNSEntries
			Specifies whether to perform DNS resolution validation of the networking information. If set to true, lookups for both forward (A) and reverse (PTR) records will be confirmed to match.

		.Parameter NTPServers
		The Network Time Protocol (NTP) servers to define for the imported appliance. Default NTP Servers to be used if none are specified are: 0.north-america.pool.ntp.org, 1.north-america.pool.ntp.org

		.Parameter PowerOn
			Specifies whether to power on the imported appliance once the import completes.

		.Notes
			Author: Steve Kaplan (steve@intolerable.net)

		.Example
			$ova = "c:\temp\nsx-v.ova"
			$dnsservers = @("10.10.1.11","10.10.1.12")
			Connect-VIServer vCenter.example.com
			$VMHost = Get-VMHost host1.example.com
			New-NSXVManager -OVFPath $ova -Name "NSX1" -VMHost $VMHost -Network "admin-network" -IPAddress "10.10.10.11" -SubnetMask "255.255.255.0" -Gateway "10.10.10.1" -DNSServers $dnsservers -Domain example.com -PowerOn

			Description
			-----------
			Deploy the NSX-V Manager Appliance with static IP settings and power it on after the import finishes
	#>
	[CmdletBinding()]
	[OutputType('VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine')]	
	Param (
		[Alias("OVA","OVF")]
		[Parameter(Mandatory=$true)]
		[ValidateScript( { Confirm-FilePath $_ } )]
		[System.IO.FileInfo]$OVFPath,

		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[String]$Name,

		[Alias("Password","AdminPassword")]
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[String]$CLIPassword,

		[Alias("EnablePassword")]
		[String]$CLIENPassword,
		[Switch]$EnableSSH,
		[bool]$EnableCEIP = $true,

		# Infrastructure Parameters
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost,
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Folder]$InventoryLocation,
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VIContainer]$Location,
		[VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$Datastore,

		[ValidateSet("Thick","Thick2GB","Thin","Thin2GB","EagerZeroedThick")]
		[String]$DiskFormat = "Thin",

		# Networking
		[Parameter(Mandatory=$true)]
		[String]$Network,

		[Parameter(Mandatory=$true)]
		[ValidateScript( {$_ -match [IPAddress]$_ })]
		[String]$IPAddress,

		[String]$SubnetMask = "255.255.255.0",

		[ValidateScript( {$_ -match [IPAddress]$_ })]
		[String]$Gateway,

		[ValidateCount(1,2)]
		[ValidateScript( {$_ -match [IPAddress]$_ })]
		[String[]]$DNSServers,
		[String]$Domain,
		[String]$FQDN,
		[bool]$ValidateDNSEntries = $true,

		[ValidateCount(1,4)]
		[String[]]$NTPServers = @("0.north-america.pool.ntp.org", "1.north-america.pool.ntp.org"),

		# Lifecycle Parameters
		[Switch]$PowerOn
	)

	Function New-Configuration () {
		$Status = "Configuring Appliance Values"
		Write-Progress -Activity $Activity -Status $Status -CurrentOperation "Extracting OVF Template"
		$ovfconfig = Get-OvfConfiguration -OvF $OVFPath.FullName
		if ($ovfconfig) {
			# Setting Basics Up
			Write-Progress -Activity $Activity -Status $Status -CurrentOperation "Configuring Basic Values"
			# Setting "admin" user password
			$ovfconfig.Common.vsm_cli_passwd_0.value = $CLIPassword 

			# Setting Enable password
			if ($CLIENPassword) { $ovfconfig.Common.vsm_cli_en_passwd_0.value = $CLIENPassword }
			else { 
				Write-Warning "A CLI Enable Password was not provided. Using the same value as -CLIPassword"
				$ovfconfig.Common.vsm_cli_en_passwd_0.value = $CLIPassword 
			}

			# Setting SSH Enablement value
			if ($EnableSSH) { $ovfconfig.Common.vsm_isSSHEnabled.value = $true }

			# Setting CEIP Enablement Value
			$ovfconfig.Common.vsm_isCEIPEnabled.value = $EnableCEIP

			# Setting Networking Values
			Write-Progress -Activity $Activity -Status $Status -CurrentOperation "Assigning Networking Values"
			$ovfconfig.NetworkMapping.VSMgmt.value = $Network; # vSphere Portgroup Network Mapping
			$ovfconfig.Common.vsm_ip_0.value = $IPAddress
			$ovfconfig.Common.vsm_netmask_0.value = $SubnetMask
			$ovfconfig.Common.vsm_gateway_0.value = $Gateway
			$ovfconfig.Common.vsm_hostname.value = $FQDN
			$ovfconfig.Common.vsm_dns1_0.value = $DNSServers -join ","
			if ($Domain) { $ovfconfig.Common.vsm_domain_0.value = $Domain }
			$ovfconfig.Common.vsm_ntp_0.value = $NTPServers -join ","

			# Returning the OVF Configuration to the function
			$ovfconfig
		}

		else { throw "The provided file '$($OVFPath)' is not a valid OVA/OVF; please check the path/file and try again" }
	}

	# Workflow to provision the NSX-V Virtual Appliance
	try {
		$Activity = "Deploying a new NSX-V Manager"

		# Validating Components
		$VMHost = Confirm-VMHost
		Confirm-BackingNetwork
		$Gateway = Set-DefaultGateway
		$FQDN = Confirm-DNS

		# Configuring the OVF Template and deploying the appliance
		$ovfconfig = New-Configuration
		if ($ovfconfig) { Import-Appliance }
		else { throw "an OVF configuration was not passed back into "}
	}

	catch { Write-Error $_ }
}

# Adding aliases and exporting this funtion when the module gets loaded
New-Alias -Value New-NSXVManager -Name New-NSXV
Export-ModuleMember -Function New-NSXVManager -Alias @("New-NSXV")