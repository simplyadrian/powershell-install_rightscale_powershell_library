# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------
Function Import-RaxHelpersAssembly()
{
	# Load RaxHelpers Assembly
	$moduleFolder = "$env:windir\system32\WindowsPowershell\v1.0\modules\RaxHelpers"
	Add-Type -Path "$moduleFolder\RaxHelpers.dll"
}

Function Get-AuthInfo
{
	Param(
		[parameter(Mandatory=$true)] [string] $userName,
		[parameter(Mandatory=$true)] [string] $apiKey,
		[parameter(Mandatory=$true)] [string] $accountRegion
	)	
	
	# Make Auth Request 
	$authClient = New-Object RaxHelpers.AuthClient
	$authClient.UserName = "$userName"
	$authClient.ApiKey = "$apiKey"
	$authClient.AccountRegion = "$accountRegion"
	
	$authClient.Authenticate()
}

Function Add-NodeToCLb()
{
	Param(
		[parameter(Mandatory=$true)] [string] $clbRegion,
		[parameter(Mandatory=$true)] [string] $accountId,		
		[parameter(Mandatory=$true)] [string] $authToken,
		[parameter(Mandatory=$true)] [string] $clbName,
		[parameter(Mandatory=$true)] [string] $ipAddress,
        [parameter(Mandatory=$true)] [string] $port
	)
	
	# Create CLoud Load Balancer Client
	$clbClient = New-Object RaxHelpers.ClbClient
	$clbClient.ClbRegion = $clbRegion
	$clbClient.AuthToken = $authToken
	$clbClient.AccountId = $accountId

	# Get My Load Balancer Id
	$loadBalancers = [RaxHelpers.Utils]::GetResponseContentXml($clbClient.Do("GET", "loadbalancers"))
	$myLoadBalancerId = ($loadBalancers.loadBalancers.loadBalancer | where {$_.Name -eq "$env:RAX_CLB_NAME"}).id

	# Add Node to Load Balancer
	$addNodeXml = @"
	<nodes xmlns="http://docs.openstack.org/loadbalancers/api/v1.0">
	    <node address="$ipAddress" port="$port" condition="ENABLED" />
	</nodes>
"@

	$response = $clbClient.Post("loadbalancers/$myLoadBalancerId/nodes",$addNodeXml)
	$responseXml = [RaxHelpers.Utils]::GetResponseContentXml($response)

	if ($response.StatusCode.ToString() -eq "422" -and $responseXml.unProcessableEntity.message.Contains("Duplicate nodes detected"))
	{
		Write-Host "Node already exists on CLB"
	}
	elseif ($response.StatusCode.ToString() -ne "200")
	{
		$responseXml.OuterXml
	}
}

Function Get-NodesInCLb()
{
	Param(
		[parameter(Mandatory=$true)] [string] $clbRegion,
		[parameter(Mandatory=$true)] [string] $accountId,		
		[parameter(Mandatory=$true)] [string] $authToken,		
		[parameter(Mandatory=$true)] [string] $clbName
	)
	
	# Create CLoud Load Balancer Client
	$clbClient = New-Object RaxHelpers.ClbClient
	$clbClient.ClbRegion = $clbRegion
	$clbClient.AuthToken = $authToken
	$clbClient.AccountId = $accountId

	# Get My Load Balancer Id
	$loadBalancers = [RaxHelpers.Utils]::GetResponseContentXml($clbClient.Do("get","loadbalancers"))
	$myLoadBalancerId = ($loadBalancers.loadBalancers.loadBalancer | where {$_.Name -eq "$clbName"}).id

	$nodes = $clbClient.DO("get","loadbalancers/$myLoadBalancerId/nodes")
	$nodesXml = [RaxHelpers.Utils]::GetResponseContentXml($nodes)
	$nodesXml.nodes.node
}

Function Remove-NodeFromCLb()
{
	Param(
		[parameter(Mandatory=$true)] [string] $clbRegion,
		[parameter(Mandatory=$true)] [string] $accountId,		
		[parameter(Mandatory=$true)] [string] $authToken,
		[parameter(Mandatory=$true)] [string] $clbName,
		[parameter(Mandatory=$true)] [string] $ipAddress
	)
	
	# Create CLoud Load Balancer Client
	$clbClient = New-Object RaxHelpers.ClbClient
	$clbClient.ClbRegion = $clbRegion
	$clbClient.AuthToken = $authToken
	$clbClient.AccountId = $accountId

	# Get My Load Balancer Id
	$loadBalancers = [RaxHelpers.Utils]::GetResponseContentXml($clbClient.Do("GET","loadbalancers"))
	$myLoadBalancerId = ($loadBalancers.loadBalancers.loadBalancer | where {$_.Name -eq "$clbName"}).id
	
	# Get node id 
	$nodes = $clbClient.DO("get","loadbalancers/$myLoadBalancerId/nodes")
	$nodesXml = [RaxHelpers.Utils]::GetResponseContentXml($nodes)
	$nodeId = ($nodesXml.nodes.node | where {$_.address -eq "$ipAddress"}).id
	
	if ($nodeId -eq $null)
	{
	 	"Node with IP Address: $ipAddress was not found in the CLB, exiting.."
		return
	}
	# Delete Node
	$response = $clbClient.Do("DELETE","loadbalancers/$myLoadBalancerId/nodes/$nodeId")
	$response = [RaxHelpers.Utils]::GetResponseContentXml($response)
	$response.OuterXml

}

Function Update-RecordInCdns()
{
	Param(
		[parameter(Mandatory=$true)] [string] $accountId,
		[parameter(Mandatory=$true)] [string] $authToken,
		[parameter(Mandatory=$true)] [string] $cDnsRegion,		
		[parameter(Mandatory=$true)] [string] $domainName,
		[parameter(Mandatory=$true)] [string] $domainRecord,
		[parameter(Mandatory=$true)] [string] $ipAddress,
		[parameter(Mandatory=$true)] [string] $dnsTtl
	)
	
	# Initialize CDNS client
	$cdnsClient = New-Object RAXHelpers.CdnsClient
	$cdnsClient.CdnsRegion = $cDnsRegion
	$cdnsClient.AccountId = $accountId
	$cdnsClient.AuthToken = $authToken
	
	# Find my domain
	$response = $cdnsClient.Do("GET","domains")
	$responseXml = [RaxHelpers.Utils]::GetResponseContentXml($response)
	$myDomainId = ($responseXml.domains.domain | where {$_.name -eq "$domainName"}).Id
	if ($myDomainId -eq $null) {
		"$domainName not found in cdns, exitting !"
		Exit 1
	}
	
	# Find records in my domain
	$response = $cdnsClient.Do("GET","domains/$myDomainId")
	$domainInfo = [RaxHelpers.Utils]::GetResponseContentXml($response)
	$recordId = ($domainInfo.domain.recordsList.record | where {$_.name -eq "$domainRecord"}).id

	# Update IPAddress for my DNS record
	$updateDnsXml = "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?><record name=""$domainRecord"" data=""$ipAddress"" ttl=""$dnsTtl"" xmlns:ns2=""http://docs.rackspacecloud.com/dns/api/management/v1.0"" xmlns=""http://docs.rackspacecloud.com/dns/api/v1.0"" xmlns:ns3=""http://www.w3.org/2005/Atom""/>"
	$response = $cdnsClient.Put("domains/$myDomainId/records/$recordId", $updateDnsXml)
	$responseXml = [RaxHelpers.Utils]::GetResponseContentXml($response)
	$responseXml.asyncResponse.status
	$responseXml.asyncResponse.request

}
# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Import-RaxHelpersAssembly

