# required modules: Az.Accounts; Az.KeyVault; SqlServer; PSFTP
# required credentials: SP-MvsDatalakeProd-credential; SP-MvsDatalakeTest-credential

$tenant = Get-AutomationVariable -Name "tenant"
$subscription = Get-AutomationVariable -Name "subscription"
$env = Get-AutomationVariable -Name "env"
$sql_user =  Get-AutomationVariable -Name "sql_user"
$ftp_server =  Get-AutomationVariable -Name "ftp_server"
$ftp_user =  Get-AutomationVariable -Name "ftp_user"
$ftp_pass =  Get-AutomationVariable -Name "ftp_pass"

$sql_server = "mvsdatalake${subscription}${env}tco1.database.windows.net"
$sql_db = "mvsdatalake-${subscription}${env}-monitoring-tco"

$sql_servers_list = @("mvsdatalaket332devhmtco", `      # dev
                      "mvsdatalaket332devtco", `
                      "mvsdatalaket332devtco1", `
                      "mvsdatalaket332integhmtco", `    # integ
                      "mvsdatalaket332integtco", `
                      "mvsdatalaket332integtco1", `
                      "mvsdatalaket332mqahmtco", `      # mqa
                      "mvsdatalaket332mqatco", `
                      "mvsdatalaket332mqatco1", `
                      "mvsdatalaket332testhmtco", `     # test
                      "mvsdatalaket332testtco", `
                      "mvsdatalaket332testtco", `
                      "mvsdatalakep332stagehmtco", `    # stage
                      "mvsdatalakep332stagetco", `
                      "mvsdatalakep332stagetco1", `
                      "mvsdatalakep332prodhmtco", `     # prod
                      "mvsdatalakep332prodtco", `
                      "mvsdatalakep332prodtco1", `
                      "mvsqacftco", `                   # qa (legacy)
                      "mvsqacftco1", `
                      "mvsqahmtco", `
                      "mvsasq001", `                    # prod (legacy)
                      "mvsasqhm001")

if ($subscription -eq "p332")
  { $SPcred = Get-AutomationPSCredential -Name 'SP-MvsDatalakeProd-credential' }
else
  { $SPcred = Get-AutomationPSCredential -Name 'SP-MvsDatalakeTest-credential' }
$app_id = $SPcred.UserName
$app_secret = $SPcred.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $app_id, $app_secret
Connect-AzAccount -Credential $Credential -Tenant "$tenant" -ServicePrincipal
$sql_pass = (Get-AzKeyVaultSecret -VaultName "tco-mvs-${subscription}${env}-kv" -Name "$sql_user").SecretValueText



Function color_definition ($days_before_the_expiration) {
    $color = ''
    if($days_before_the_expiration -le "0")
      { $color = "color:red" }
    else
      {
        if($days_before_the_expiration -le "14")
          { $color = "color:orange" }
        else
          { $color = "color:green" }
      }
    return $color
}

Function credentials_expiration_raw_generation ($name, $id, $days_before_the_expiration, $datetime) {
    $raw_color = color_definition $days_before_the_expiration
    $raw = "
        <tr style=font-weight:bold;$raw_color>
          <td>$name</td>
          <td>$id</td>
          <td>$days_before_the_expiration</td>
          <td>$datetime</td>
        </tr>
    "
    Out-File -FilePath second.html -InputObject $raw -Append
}



$datetime = (Get-Date -Format "yyyy-MM-dd  HH:mm:ss")
$page_header = "
    <!DOCTYPE html> 
    <html> 
      <head> 
        <meta http-equiv=refresh content=60>
        <style>
          ul { list-style-type: none; margin: 0; padding: 0; overflow: hidden; background-color: #333 }
          li { float: left; font-weight: bold; font-size: 150% }
          li a { display: block; color: white; text-align: center; padding: 15px 30px; text-decoration: none }
          li a:hover:not(.active) { background-color: #111}
          .active { background-color: #4CAF50 }
        </style>
      </head>
      <body style='background-color:#ddd'>
        <ul>
          <li><a href='index.html'>${subscription}${env} Databricks jobs statuses and data availability information</a></li>
          <li><a class='active' href='second.html'>Expiration information</a></li>
        </ul>
        <script> 
          var today = new Date();
          var date = today.getUTCFullYear() + '-' + (today.getUTCMonth() + 1) + '-' + today.getUTCDate();
          var time = today.getUTCHours() + ':' + today.getUTCMinutes() + ':' + today.getUTCSeconds() + ' (UTC)';
          var datetime = date + '  ' + time;
          document.write('<h2>Current date and time: ' + datetime + '</h2>');
        </script>
        <h2>Last information update: $datetime (UTC)</h2>
        <table cellpadding=10 cellspacing=10 style=width:100%>
          <tr style=vertical-align:top>
"
Out-File -FilePath second.html -InputObject $page_header



$app_certificates_count = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query "SELECT COUNT(DISTINCT credential_key_id) AS number FROM app_credentials_expiration WHERE type='AsymmetricX509Cert'").number

$app_certificates_query = "SELECT app_name, credential_key_id, days_before_the_expiration, datetime FROM app_credentials_expiration WHERE type='AsymmetricX509Cert'"
$app_certificates_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $app_certificates_query)

$app_certificates_table_header = "
    <td> 
      <table border=3 cellpadding=3 style=width:100%>
      <caption style=font-weight:bold;font-size:200%>Application certificates expiration</caption>
        <tr style=font-weight:bold;font-size:125%;text-align:center;vertical-align:middle> 
          <td>Applcation name</td>
          <td>Certificate ID</td>
          <td>Days before the<br>certificate expiration</td>
          <td>DateTime of record<br>update in database (UTC)</td>
        </tr>
"
Out-File -FilePath second.html -InputObject $app_certificates_table_header -Append

for ( $i = 0; $i -lt $app_certificates_count; $i++ ) {
    credentials_expiration_raw_generation $app_certificates_query_result.app_name[$i] `
                                          $app_certificates_query_result.credential_key_id[$i] `
                                          $app_certificates_query_result.days_before_the_expiration[$i] `
                                          $app_certificates_query_result.datetime[$i]                                     
}

$app_certificates_table_ending = "</table> </td>"
Out-File -FilePath second.html -InputObject $app_certificates_table_ending -Append



$app_passwords_count = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query "SELECT COUNT(DISTINCT credential_key_id) AS number FROM app_credentials_expiration WHERE type='Password'").number

$app_passwords_query = "SELECT app_name, credential_key_id, days_before_the_expiration, datetime FROM app_credentials_expiration WHERE type='Password'"
$app_passwords_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $app_passwords_query)

$app_passwords_table_header = "
    <td> 
      <table border=3 cellpadding=3 style=width:100%>
      <caption style=font-weight:bold;font-size:200%>Application passwords expiration</caption>
        <tr style=font-weight:bold;font-size:125%;text-align:center;vertical-align:middle> 
          <td>Application name</td>
          <td>Password ID</td>
          <td>Days before the<br>password expiration</td>
          <td>DateTime of record<br>update in database (UTC)</td>
        </tr>
"
Out-File -FilePath second.html -InputObject $app_passwords_table_header -Append

for ( $i = 0; $i -lt $app_passwords_count; $i++ ) {
    credentials_expiration_raw_generation $app_passwords_query_result.app_name[$i] `
                                          $app_passwords_query_result.credential_key_id[$i] `
                                          $app_passwords_query_result.days_before_the_expiration[$i] `
                                          $app_passwords_query_result.datetime[$i]                                     
}

$app_passwords_table_ending = "</table> </td> </tr>"
Out-File -FilePath second.html -InputObject $app_passwords_table_ending -Append



$sql_passwords_query = "SELECT expiry_date, days_before_the_expiration, datetime FROM sql_password_expiration"
$sql_passwords_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $sql_passwords_query)

$sql_passwords_days_before_the_expiration = $sql_passwords_query_result.days_before_the_expiration
$sql_passwords_datetime = $sql_passwords_query_result.datetime

$sql_servers = $sql_servers_list[0]
for ( $i = 1; $i -lt $sql_servers_list.length; $i++ ) {
    if ($i % 3 -eq 0 ) 
      { $sql_servers = "$sql_servers;<br>" + $sql_servers_list[$i] }
    else
      { $sql_servers = "$sql_servers,   " + $sql_servers_list[$i] }
}

$sql_color = color_definition $sql_passwords_days_before_the_expiration

$sql_passwords_table = "
    <tr style=vertical-align:top>
      <td> 
        <table border=3 cellpadding=3 style=width:100%>
        <caption style=font-weight:bold;font-size:200%>SQL server passwords expiration</caption>
          <tr style=font-weight:bold;font-size:125%;text-align:center;vertical-align:middle> 
            <td>SQL servers</td>
            <td>Days before the<br>password expiration</td>
            <td>DateTime of record<br>update in database (UTC)</td>
          </tr>
          <tr style=font-weight:bold;$sql_color>
            <td>$sql_servers</td>          
            <td style=font-size:150%;text-align:center>$sql_passwords_days_before_the_expiration</td>
            <td style=font-size:150%;text-align:center>$sql_passwords_datetime</td>
          </tr>
        </table> 
      </td>
"
Out-File -FilePath second.html -InputObject $sql_passwords_table -Append  



$databricks_tokens_count = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query "SELECT COUNT(DISTINCT token_id) AS number FROM databricks_tokens_expiration").number

$databricks_tokens_query = "SELECT subscription, environment, token_id, days_before_the_expiration, datetime FROM databricks_tokens_expiration"
$databricks_tokens_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $databricks_tokens_query)

$databricks_tokens_table_header = "
    <td> 
      <table border=3 cellpadding=3 style=width:100%>
      <caption style=font-weight:bold;font-size:200%>Databricks tokens expiration</caption>
        <tr style=font-weight:bold;font-size:125%;text-align:center;vertical-align:middle> 
          <td>Subscription and<br>environment</td>
          <td>Token ID</td>
          <td>Days before the<br>token expiration</td>
          <td>DateTime of record<br>update in database (UTC)</td>
        </tr>
"
Out-File -FilePath second.html -InputObject $databricks_tokens_table_header -Append

for ( $i = 0; $i -lt $databricks_tokens_count; $i++ ) {
    $databricks_sub = $databricks_tokens_query_result.subscription[$i]
    $databricks_env = $databricks_tokens_query_result.environment[$i]
    $databricks_sub_env = "$databricks_sub-$databricks_env"
    credentials_expiration_raw_generation $databricks_sub_env `
                                          $databricks_tokens_query_result.token_id[$i] `
                                          $databricks_tokens_query_result.days_before_the_expiration[$i] `
                                          $databricks_tokens_query_result.datetime[$i]                                     
}

$databricks_tokens_table_ending = "</table> </td>"
Out-File -FilePath second.html -InputObject $databricks_tokens_table_ending -Append



$page_ending = "</tr> </table> </body> </html>"
Out-File -FilePath second.html -InputObject $page_ending -Append



$ftp_password = ConvertTo-SecureString $ftp_pass -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential($ftp_user,$ftp_password)
Set-FTPConnection -Credentials $creds -Server $ftp_server -Session FTPsession -UsePassive 
$Session = Get-FTPConnection -Session FTPsession 
Add-FTPItem -Session $Session -Path /site/wwwroot/ -LocalPath second.html -Overwrite