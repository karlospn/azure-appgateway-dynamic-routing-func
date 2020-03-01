using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$req = $Request |   ConvertTo-Json
Write-Host "Incoming Request: $req "

function GetApplicationGateway($gatewayName, $resGroup)
{
    $gateway = Get-AzApplicationGateway -Name $gatewayName -ResourceGroupName $resGroup -ErrorAction Stop
    
    if($null -eq $gateway)
    {
        Throw "Gateway is null"
    }

    return $gateway
}

function GetBackendPool($gw)
{
    $backend = Get-AzApplicationGatewayBackendAddressPool -ApplicationGateway $gw -ErrorAction Stop

    if($null -eq $backend)
    {
        Throw "BackendPool is null"
    }

    return $backend
}

function AddProbeToApplicationGateway($gw, $protocol, $appServiceHostname)
{
    $probeName = $appName + "_probe"
    $probeHc = New-AzApplicationGatewayProbeHealthResponseMatch -Body null -StatusCode "200-399" -ErrorAction Stop
    
    Add-AzApplicationGatewayProbeConfig `
    -ApplicationGateway $gw `
    -Name $probeName `
    -Protocol $protocol `
    -HostName $appServiceHostname `
    -Path "/health.svc/health" `
    -Interval 30 `
    -Timeout 50 `
    -UnhealthyThreshold 5 `
    -Match $probeHc `
    -ErrorAction Stop | Out-Null

    return Get-AzApplicationGatewayProbeConfig -ApplicationGateway $gw -Name $probeName    
}

function AddHttpSettingsToApplicationGateway($gw, $protocol, $appServiceHostname, $appProbe)
{
    $httpSettingName = $appName + "_HttpSetting"

    Add-AzApplicationGatewayBackendHttpSetting `
    -ApplicationGateway $gw `
    -Name $httpSettingName `
    -Port 80 `
    -Protocol $protocol `
    -CookieBasedAffinity "Disabled" `
    -path "/" `
    -hostName $appServiceHostname `
    -Probe $appProbe `
    -ErrorAction Stop | Out-Null

    $settings = Get-AzApplicationGatewayBackendHttpSettings -ApplicationGateway $gw | Where-Object { $_.Name -eq $httpSettingName }

    if($null -eq $settings)
    {
        Throw "HttpSettings not found"
    }

    return $settings
}

function UpdateUrlPathMapToApplicationGateway($gw, $pathRulePath, $backendPool, $httpSettings)
{
    $prcName = $appName + "_pathRuleConfig"

    $newPathRule = New-AzApplicationGatewayPathRuleConfig `
    -Name $prcName `
    -Paths $pathRulePath `
    -BackendAddressPool $backendPool `
    -BackendHttpSettings $httpSettings `
    -ErrorAction Stop

    $pathMap = Get-AzApplicationGatewayUrlPathMapConfig -ApplicationGateway $gw -Name "ase_rule" -ErrorAction Stop
    $pathRules = $pathmap.PathRules.ToArray()
    $pathRules += $newPathRule

    Set-AzApplicationGatewayUrlPathMapConfig `
        -ApplicationGateway $gw `
        -Name $pathMap.Name `
        -PathRules $pathRules `
        -DefaultBackendAddressPool $backendPool `
        -DefaultBackendHttpSettings $httpSettings `
        -ErrorAction Stop | Out-Null
}

function GetSubscription($uri)
{
    $subs = $uri.Split('/')
    $index = $subs.IndexOf('subscriptions')
    return $subs[$index + 1]
}

function GetResourceGroup($uri)
{
    $res = $uri.Split('/')
    $index = $res.IndexOf('resourceGroups')
    return $res[$index + 1]
}

function GetCustomResourceName($uri)
{
    $resName = $uri.Split('/')
    $index = $resName.IndexOf('resourceProviders')
    return $resName[$index + 3]
}

function GetResourceTypeName($uri)
{
    $resType = $uri.Split('/')
    $index = $resType.IndexOf('resourceProviders')
    return $resType[$index + 2]
}

$gatewayName = $Request.Body.properties.gatewayName
$resGroup = $Request.Body.properties.resGroup
$appName = $Request.Body.properties.appName
$protocol = $Request.Body.properties.protocol
$appServiceHostname = $Request.Body.properties.appServiceHostname
$pathRulePath = $Request.Body.properties.pathRulePath


Write-Host "Get the property gatewayName: $gatewayName"
Write-Host "Get the property resGroup: $resGroup"
Write-Host "Get the property appName: $appName"
Write-Host "Get the property protocol: $protocol"
Write-Host "Get the property appServiceHostname: $appServiceHostname"
Write-Host "Get the property pathRulePath: $pathRulePath"


if ($null -eq $gatewayName -or `
    $null -eq $resGroup -or `
    $null -eq $appName -or `
    $null -eq $protocol -or `
    $null -eq $appServiceHostname -or `
    $null -eq $pathRulePath) {

        $status = [HttpStatusCode]::BadRequest
        $body = "Missing parameters on the request body."
}
else {

    try {

        $gw = GetApplicationGateway $gatewayName $resGroup
        $backendPool = GetBackendPool $gw
        $appProbe = AddProbeToApplicationGateway $gw $protocol $appServiceHostname
        $httpSettings = AddHttpSettingsToApplicationGateway $gw $protocol $appServiceHostname $appProbe
        UpdateUrlPathMapToApplicationGateway $gw $pathRulePath $backendPool $httpSettings
        Set-AzApplicationGateway -ApplicationGateway $gw -ErrorAction Stop | Out-Null
        $status = [HttpStatusCode]::OK
        $body = "Everything went OK"
    }
    catch {
        $status = [HttpStatusCode]::BadRequest
        $body = $_.Exception.Message
    }   
}

$uri =   $Request.Headers["x-ms-customproviders-requestpath"]

Write-Host "Uri header : $uri"

$subscription = GetSubscription($uri)
$resourceGroup = GetResourceGroup($uri)
$customResourceName = GetCustomResourceName($uri)
$resourceTypeName = GetResourceTypeName($uri)

$id = "/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.CustomProviders/resourceProviders/$customResourceName"
$name = $customResourceName
$type = "Microsoft.CustomProviders/resourceProviders/$resourceTypeName"

$responseBody = @"
{
    "id": "$($id)",
    "type": "$($type)",
    "name": "$($name)",
    "properties": "$($body)"
}
"@

Write-Host "Response Body: $responseBody"
Write-Host "Status: $status"

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{    
    StatusCode = $status
    Body = $responseBody
    ContentType = 'application/json'
})

