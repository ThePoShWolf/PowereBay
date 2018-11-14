Add-Type -AssemblyName System.Web
Function Get-eBayAuthenticationCode {
    [cmdletbinding()]
    Param(
        [string]$ClientID,
        [string]$RUName
    )
    <#
        Doc on flow: https://developer.ebay.com/api-docs/static/oauth-authorization-code-grant.html
    #>
    #$encodedAuthorization = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes("$ClientID`:$ClientSecret"))
    $encodedClientID = [System.Web.HttpUtility]::UrlEncode($ClientID)
    $encodedRUName = [System.Web.HttpUtility]::UrlEncode($RUName)
    $baseUri = 'https://auth.ebay.com/oauth2/authorize'
    $scope = 'https://api.ebay.com/oauth/api_scope/sell.inventory%20https://api.ebay.com/oauth/api_scope/sell.fulfillment'
    $logonUri = "$baseUri`?client_id=$encodedClientID&redirect_uri=$encodedRUName&response_type=code&scope=$scope&prompt=login"
    Write-Verbose "Logon URL: $logonUri"
    $Form = New-Object -TypeName 'System.Windows.Forms.Form' -Property @{
        Width = 680
        Height = 640
    }
    $Web = New-Object -TypeName 'System.Windows.Forms.WebBrowser' -Property @{
        Width = 680
        Height = 640
        Url = $logonUri
    }
    $DocumentCompleted_Script = {
        if ($web.Url.AbsoluteUri -match "error=[^&]*|code=[^&]*") {
            $form.Close()
        }
    }
    $web.ScriptErrorsSuppressed = $true
    $web.Add_DocumentCompleted($DocumentCompleted_Script)
    $form.Controls.Add($web)
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()

    $QueryOutput = [System.Web.HttpUtility]::ParseQueryString($web.Url.Query)
    $Response = @{ }
    foreach ($key in $queryOutput.Keys) {
        $Response["$key"] = $QueryOutput[$key]
    }
    If($Response['isAuthSuccessful']){
        $Response['code']
    }Else{
        Throw 'Error'
    }
}
#https://developer.ebay.com/api-docs/sell/fulfillment/resources/order/methods/getOrders
#https://developer.ebay.com/api-docs/sell/fulfillment/resources/order/methods/getOrder
Function Get-eBayOrder {
    [cmdletbinding(
        DefaultParameterSetName = 'MultipleOrders'
    )]
    Param(
        [string]$Token, #should be replaced with some sort of global variable or something
        [Parameter(
            ParameterSetName = 'SingleOrder'
        )]
        [string]$OrderID,
        [Parameter(
            ParameterSetName = 'MultipleOrders'
        )]
        [string[]]$OrderIDs,
        #region filter options
        [datetime]$CreationDateStart,
        [datetime]$CreationDateEnd,
        [datetime]$LastModifiedDateStart,
        [datetime]$LastModifiedDateEnd,
        [ValidateSet('NOT_STARTED','IN_PROGRESS','FULFILLED')]
        [string]$OrderFulfillmentStatus
        #endregion
    )
    $baseUri = 'https://api.ebay.com/sell/fulfillment/v1/order'
    $headers = @{
        Authorization = "Bearer $token"
        Accept = 'application/json'
    }
    If($PSCmdlet.ParameterSetName -eq 'SingleOrder'){
        Invoke-RestMethod -Method Get -Uri "$baseUri/$OrderID" -Headers $headers
    }ElseIf($PSCmdlet.ParameterSetName -eq 'MultipleOrders'){
        # %5B and %5D are: [ ]
        # .000Z is added because the API spec requires it but PS doesn't add it by default with '-Format s'
        If($CreationDateStart){
            $creationDateFilter = 'creationdate:%5B{CreationDateStart}..{CreationDateEnd}%5D'
            $CreationDateStartUTC = Get-Date -Date $CreationDateStart.ToUniversalTime() -Format s
            $creationDateFilter = $creationDateFilter -replace '{CreationDateStart}',"$CreationDateStartUTC.000Z"
            If($CreationDateEnd){
                $CreationDateEndUTC = Get-Date -Date $CreationDateEnd.ToUniversalTime() -Format s
                $creationDateFilter = $creationDateFilter -replace '{CreationDateEnd}',"$CreationDateEndUTC.000Z"
            }Else{
                $creationDateFilter = $creationDateFilter -replace '{CreationDateEnd}',''
            }
        }
        If($creationDateFilter){
            $filter = "filter=$creationDateFilter"
        }
        Write-Verbose "$baseUri`?$filter"
        Invoke-RestMethod -Uri "$baseUri`?$filter" -Headers $headers
    }
}
#https://developer.ebay.com/api-docs/sell/fulfillment/resources/order/shipping_fulfillment/methods/getShippingFulfillments
#https://developer.ebay.com/api-docs/sell/fulfillment/resources/order/shipping_fulfillment/methods/getShippingFulfillment
Function Get-eBayShippingFulfillment {
    Param(
        [string]$OrderID,
        [string]$FulfillmentID,
        [string]$Token
    )
    $baseUri = 'https://api.ebay.com/sell/fulfillment/v1/order/{orderId}/shipping_fulfillment' -replace '{orderid}',$OrderID
    If($FulfillmentID){
        $baseUri = "$baseUri/$FulfillmentID"
    }
    $headers = @{
        Authorization = "Bearer $token"
        Accept = 'application/json'
    }
    Invoke-RestMethod -Method Get -Uri $baseUri -Headers $headers
}
Function Get-eBayUserToken {
    [cmdletbinding()]
    Param(
        [string]$ClientID,
        [string]$ClientSecret,
        [string]$RuName,
        [string]$AuthorizationCode
    )
    $baseUri = 'https://api.ebay.com/identity/v1/oauth2/token/'
    # Doc on auth format: https://developer.ebay.com/api-docs/static/oauth-base64-credentials.html
    $encodedAuthorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$ClientID`:$ClientSecret")) #this is broken
    Write-Verbose $encodedAuthorization
    $headers = @{
        'Content-Type' = 'application/x-www-form-urlencoded'
        Authorization = "Basic $encodedAuthorization"
    }
    Write-Verbose $headers.ToString()

    $encodedAuthCode = [System.Web.HttpUtility]::UrlEncode($AuthorizationCode)
    $encodedRUName = [System.Web.HttpUtility]::UrlEncode($RuName)

    $body = @(
        "grant_type=authorization_code"
        "&code=$encodedAuthCode"
        "&redirect_uri=$encodedRUName"
    ) -join ''
    Write-Verbose $body.ToString()

    #Invoke-RestMethod -Uri $baseUri -Body $body -Headers $headers -Method Post
    $response = Invoke-WebRequest -Uri $baseUri -Body $body -Headers $headers -Method Post
    $response.Content | ConvertFrom-Json
}
