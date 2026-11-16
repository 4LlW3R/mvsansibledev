# required modules: Az.Accounts; Az.KeyVault; SqlServer
# required credentials: SP-MvsDatalakeProd-credential; SP-MvsDatalakeTest-credential

$tenant = Get-AutomationVariable -Name "tenant"
$subscription = Get-AutomationVariable -Name "subscription"
$env = Get-AutomationVariable -Name "env"
$sql_user =  Get-AutomationVariable -Name "sql_user"
$smtp_server = Get-AutomationVariable -Name "smtp_server"
$smtp_port = Get-AutomationVariable -Name "smtp_port"
$smtp_login = Get-AutomationVariable -Name "smtp_login"

$sql_server = "mvsdatalake${subscription}${env}tco1.database.windows.net"
$sql_db = "mvsdatalake-${subscription}${env}-monitoring-tco"
$sender = "Service TCO-DATA notifyer <$smtp_login@tengizchevroil.com>"
$monitoring_dashboard_link = "https://mvsdatalake-${subscription}${env}-monitoring-tco.azurewebsites.net/second.html"

$maillist = 'Konstantin Farvazov <Konstantin_Farvazov@epam.com>', `
            'Kseniia Iashina <Kseniia_Iashina@epam.com>', `
            'Andrei Bespalov <andrei_bespalov@epam.com>', `
            'Nikita Poberezkin <Nikita_Poberezkin@epam.com>', `
            'Dmitriy Kozhin <Dmitriy_Kozhin@epam.com>', `
            'Valerii Florov <Valerii_Florov@epam.com>', `
            'Pozhidayev, Vassiliy S. [Tengizchevroil] <V.Pozhidayev@tengizchevroil.com>', `
            'tcomvssupport@chevron.com'

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
$smtp_pass = (Get-AzKeyVaultSecret -VaultName "mvsdatalake-${subscription}-cvx" -Name 'ado-smtp-password').SecretValue



$message = ""

Function send_message ($message_body, $subject) {
    $SMTPcreds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $smtp_login, $smtp_pass
    Send-MailMessage `
        -SmtpServer $smtp_server `
        -Port $smtp_port `
        -Credential $SMTPcreds `
        -UseSsl `
        -From $sender `
        -To $maillist `
        -Subject "${subscription}${env} monitoring system warning [$subject]" `
        -BodyAsHtml $message_body
}



#Applications certificates
$app_certs_expired_query = "SELECT app_name, credential_key_id, days_before_the_expiration FROM app_credentials_expiration WHERE type='AsymmetricX509Cert' AND days_before_the_expiration <= 0"
$app_certs_expired_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $app_certs_expired_query)
if ( $app_certs_expired_query_result ) {
    $message = "$message `n<h4 style=color:red> `n  <p>Application certificates expired:</p> `n</h4> `n<ul>"
    if ( $app_certs_expired_query_result.GetType().FullName -eq "System.Data.DataRow" ) {
        $app_name = $app_certs_expired_query_result.app_name
        $certificate_id = $app_certs_expired_query_result.credential_key_id
        $days_before_the_expiration = $app_certs_expired_query_result.days_before_the_expiration
        $days_after_expiration = $days_before_the_expiration*(-1)
        $message = "$message `n  <li>Certificate [id: $certificate_id] of SP <b>$app_name</b> expired <b>$days_after_expiration</b> days ago </li>"
    }
    else {
        for ( $i = 0; $i -lt $app_certs_expired_query_result.Length; $i++ ) {
            $app_name = $app_certs_expired_query_result.app_name[$i]
            $certificate_id = $app_certs_expired_query_result.credential_key_id[$i]
            $days_before_the_expiration = $app_certs_expired_query_result.days_before_the_expiration[$i]
            $days_after_expiration = $days_before_the_expiration*(-1)
            $message = "$message `n  <li>Certificate [id: $certificate_id] of SP <b>$app_name</b> expired <b>$days_after_expiration</b> days ago </li>"
        }
    }
    $message = "$message `n</ul>"
}

$app_certs_expire_soon_query = "SELECT app_name, credential_key_id, days_before_the_expiration FROM app_credentials_expiration WHERE type='AsymmetricX509Cert' AND days_before_the_expiration > 0 AND days_before_the_expiration <= 14"
$app_certs_expire_soon_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $app_certs_expire_soon_query)
if ( $app_certs_expire_soon_query_result ) {
    $message = "$message `n<h4 style=color:orange> `n  <p>Application certificates will expire soon:</p> `n</h4> `n<ul>"
    if ( $app_certs_expire_soon_query_result.GetType().FullName -eq "System.Data.DataRow" ) {
        $app_name = $app_certs_expire_soon_query_result.app_name
        $certificate_id = $app_certs_expire_soon_query_result.credential_key_id
        $days_before_the_expiration = $app_certs_expire_soon_query_result.days_before_the_expiration
        $message = "$message `n  <li>Certificate [id: $certificate_id] of SP <b>$app_name</b> will expire after <b>$days_before_the_expiration</b> days </li>"
    }
    else {
        for ( $i = 0; $i -lt $app_certs_expire_soon_query_result.Length; $i++ ) {
            $app_name = $app_certs_expire_soon_query_result.app_name[$i]
            $certificate_id = $app_certs_expire_soon_query_result.credential_key_id[$i]
            $days_before_the_expiration = $app_certs_expire_soon_query_result.days_before_the_expiration[$i]
            $message = "$message `n  <li>Certificate [id: $certificate_id] of SP <b>$app_name</b> will expire after <b>$days_before_the_expiration</b> days </li>"
        }
    }
    $message = "$message `n</ul>"
}



#Applications passwords
$app_passwords_expired_query = "SELECT app_name, credential_key_id, days_before_the_expiration FROM app_credentials_expiration WHERE type='Password' AND days_before_the_expiration <= 0"
$app_passwords_expired_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $app_passwords_expired_query)
if ( $app_passwords_expired_query_result ) {
    $message = "$message `n<h4 style=color:red> `n  <p>Application passwords expired:</p> `n</h4> `n<ul>"
    if ( $app_passwords_expired_query_result.GetType().FullName -eq "System.Data.DataRow" ) {
        $app_name = $app_passwords_expired_query_result.app_name
        $password_id = $app_passwords_expired_query_result.credential_key_id
        $days_before_the_expiration = $app_passwords_expired_query_result.days_before_the_expiration
        $days_after_expiration = $days_before_the_expiration*(-1)
        $message = "$message `n  <li>Password [id: $password_id] of SP <b>$app_name</b> expired <b>$days_after_expiration</b> days ago </li>"
    }
    else {
        for ( $i = 0; $i -lt $app_passwords_expired_query_result.Length; $i++ ) {
            $app_name = $app_passwords_expired_query_result.app_name[$i]
            $password_id = $app_passwords_expired_query_result.credential_key_id[$i]
            $days_before_the_expiration = $app_passwords_expired_query_result.days_before_the_expiration[$i]
            $days_after_expiration = $days_before_the_expiration*(-1)
            $message = "$message `n  <li>Password [id: $password_id] of SP <b>$app_name</b> expired <b>$days_after_expiration</b> days ago </li>"
        }
    }
    $message = "$message `n</ul>"
}

$app_passwords_expire_soon_query = "SELECT app_name, credential_key_id, days_before_the_expiration FROM app_credentials_expiration WHERE type='Password' AND days_before_the_expiration > 0 AND days_before_the_expiration <= 14"
$app_passwords_expire_soon_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $app_passwords_expire_soon_query)
if ( $app_passwords_expire_soon_query_result ) {
    $message = "$message `n<h4 style=color:orange> `n  <p>Application passwords will expire soon:</p> `n</h4> `n<ul>"
    if ( $app_passwords_expire_soon_query_result.GetType().FullName -eq "System.Data.DataRow" ) {
        $app_name = $app_passwords_expire_soon_query_result.app_name
        $password_id = $app_passwords_expire_soon_query_result.credential_key_id
        $days_before_the_expiration = $app_passwords_expire_soon_query_result.days_before_the_expiration
        $message = "$message `n  <li>Password [id: $password_id] of SP <b>$app_name</b> will expire after <b>$days_before_the_expiration</b> days </li>"
    }
    else {
        for ( $i = 0; $i -lt $app_passwords_expire_soon_query_result.Length; $i++ ) {
            $app_name = $app_passwords_expire_soon_query_result.app_name[$i]
            $password_id = $app_passwords_expire_soon_query_result.credential_key_id[$i]
            $days_before_the_expiration = $app_passwords_expire_soon_query_result.days_before_the_expiration[$i]
            $message = "$message `n  <li>Password [id: $password_id] of SP <b>$app_name</b> will expire after <b>$days_before_the_expiration</b> days </li>"
        }
    }
    $message = "$message `n</ul>"
}



#Databricks tokens
$db_tokens_expired_query = "SELECT subscription, environment, token_id, days_before_the_expiration FROM databricks_tokens_expiration WHERE days_before_the_expiration <= 0"
$db_tokens_expired_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $db_tokens_expired_query)
if ( $db_tokens_expired_query_result ) {
    $message = "$message `n<h4 style=color:red> `n  <p>Databricks tokens expired:</p> `n</h4> `n<ul>"
    if ( $db_tokens_expired_query_result.GetType().FullName -eq "System.Data.DataRow" ) {
        $sub = $db_tokens_expired_query_result.subscription
        $env = $db_tokens_expired_query_result.environment
        $token_id = $db_tokens_expired_query_result.token_id
        $days_before_the_expiration = $db_tokens_expired_query_result.days_before_the_expiration
        $days_after_expiration = $days_before_the_expiration*(-1)
        $message = "$message `n  <li>Token [id: $token_id] on <b>$sub$env</b> expired <b>$days_after_expiration</b> days ago </li>"
    }
    else {
        for ( $i = 0; $i -lt $db_tokens_expired_query_result.Length; $i++ ) {
            $sub = $db_tokens_expired_query_result.subscription[$i]
            $env = $db_tokens_expired_query_result.environment[$i]
            $token_id = $db_tokens_expired_query_result.token_id[$i]
            $days_before_the_expiration = $db_tokens_expired_query_result.days_before_the_expiration[$i]
            $days_after_expiration = $days_before_the_expiration*(-1)
            $message = "$message `n  <li>Token [id: $token_id] on <b>$sub$env</b> expired <b>$days_after_expiration</b> days ago </li>"
        }
    }
    $message = "$message `n</ul>"
}

$db_tokens_expire_soon_query = "SELECT subscription, environment, token_id, days_before_the_expiration FROM databricks_tokens_expiration WHERE days_before_the_expiration > 0 AND days_before_the_expiration <= 14"
$db_tokens_expire_soon_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $db_tokens_expire_soon_query)
if ( $db_tokens_expire_soon_query_result ) {
    $message = "$message `n<h4 style=color:orange> `n  <p>Databricks tokens will expire soon:</p> `n</h4> `n<ul>"
    if ( $db_tokens_expire_soon_query_result.GetType().FullName -eq "System.Data.DataRow" ) {
        $sub = $db_tokens_expire_soon_query_result.subscription
        $env = $db_tokens_expire_soon_query_result.environment
        $token_id = $db_tokens_expire_soon_query_result.token_id
        $days_before_the_expiration = $db_tokens_expire_soon_query_result.days_before_the_expiration
        $message = "$message `n  <li>Token [id: $token_id] on <b>$sub$env</b> will expire after <b>$days_before_the_expiration</b> days </li>"
    }
    else {
        for ( $i = 0; $i -lt $db_tokens_expire_soon_query_result.Length; $i++ ) {
            $sub = $db_tokens_expire_soon_query_result.subscription[$i]
            $env = $db_tokens_expire_soon_query_result.environment[$i]
            $token_id = $db_tokens_expire_soon_query_result.token_id[$i]
            $days_before_the_expiration = $db_tokens_expire_soon_query_result.days_before_the_expiration[$i]
            $message = "$message `n  <li>Token [id: $token_id] on <b>$sub$env</b> will expire after <b>$days_before_the_expiration</b> days </li>"
        }
    }
    $message = "$message `n</ul>"
}



#SQL servers passwords
$sql_password_expired_query = "SELECT days_before_the_expiration FROM sql_password_expiration WHERE days_before_the_expiration <= 0"
$sql_password_expired_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $sql_password_expired_query)
if ( $db_tokens_expired_query_result ) {
    $days_before_the_expiration = $sql_password_expired_query_result.days_before_the_expiration
    $days_after_expiration = $days_before_the_expiration*(-1)
    $message = "$message `n<h4 style=color:red> `n  <p>SQL password expired $days_after_expiration days ago and should be changed for all active servers:</p> `n</h4> `n<ul>"
    for ( $i = 0; $i -lt $sql_servers_list.length; $i++ ) {
        $message = "$message `n  <li>" + $sql_servers_list[$i] + "</li>"
    }
    $message = "$message `n</ul>"
}

$sql_password_expire_soon_query = "SELECT days_before_the_expiration FROM sql_password_expiration WHERE days_before_the_expiration > 0 AND days_before_the_expiration <= 14"
$sql_password_expire_soon_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $sql_password_expire_soon_query)
if ( $sql_password_expire_soon_query_result ) {
    $days_before_the_expiration = $sql_password_expire_soon_query_result.days_before_the_expiration
    $message = "$message `n<h4 style=color:orange> `n  <p>SQL password will expire after $days_before_the_expiration days and should be changed for all active servers:</p> `n</h4> `n<ul>"
    for ( $i = 0; $i -lt $sql_servers_list.length; $i++ ) {
        $message = "$message `n  <li>" + $sql_servers_list[$i] + "</li>"
    }
    $message = "$message `n</ul>"
}



if ($message) { send_message $message 'expiration issues' }