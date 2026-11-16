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
$monitoring_dashboard_link = "https://mvsdatalake-${subscription}${env}-monitoring-tco.azurewebsites.net"

$maillist = 'Konstantin Farvazov <Konstantin_Farvazov@epam.com>', `
            'Kseniia Iashina <Kseniia_Iashina@epam.com>', `
            'Andrei Bespalov <andrei_bespalov@epam.com>', `
            'Nikita Poberezkin <Nikita_Poberezkin@epam.com>', `
            'Dmitriy Kozhin <Dmitriy_Kozhin@epam.com>', `
            'Valerii Florov <Valerii_Florov@epam.com>', `
            'Pozhidayev, Vassiliy S. [Tengizchevroil] <V.Pozhidayev@tengizchevroil.com>', `
            'tcomvssupport@chevron.com'

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



$lack_of_data_query = "
    SELECT t1.table_name, t1.query_responce, t1.monitoring_period_in_minutes
    FROM data_existence t1
    INNER JOIN
    (
      SELECT table_name, MAX(datetime) AS max_datetime
      FROM data_existence
      GROUP BY table_name
    ) t2
    ON t1.table_name = t2.table_name AND t1.datetime = t2.max_datetime
    WHERE t1.query_responce=0
"
$data_existence_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $lack_of_data_query)

if ( $data_existence_query_result ) {
    $message = "<h4> `n  <p>Data availability issues have been detected by monitoring system. See <a href=$monitoring_dashboard_link>MONITORING DASHBOARD</a> for details.</p> `n  <p>List of Data Lake tables with data availability problems:</p> `n</h4> `n<ul>"
    if ( $data_existence_query_result.GetType().FullName -eq "System.Data.DataRow" ) {
        $table_name = $data_existence_query_result.table_name
        $monitoring_period = $data_existence_query_result.monitoring_period_in_minutes
        $message = "$message `n  <li>$table_name  (monitoring period: $monitoring_period minutes) </li>"
    }
    else {
        for ( $i = 0; $i -lt $data_existence_query_result.Length; $i++ ) {
            $table_name = $data_existence_query_result.table_name[$i]
            $monitoring_period = $data_existence_query_result.monitoring_period_in_minutes[$i]
            $message = "$message `n  <li>$table_name  (monitoring period: $monitoring_period minutes) </li>"
        }
    }
    $message = "$message `n</ul>"
    send_message $message 'data availability issues'
}



$jobs_restart_query = "
    SELECT run_id, job_name, life_cycle_state, result_state, run_link FROM jobs_statuses
    WHERE run_trigger='RETRY' and DATEDIFF(hour, CAST(run_start_time AS datetime), CURRENT_TIMESTAMP) = 1
"
$jobs_restart_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $jobs_restart_query)

if ( $jobs_restart_query_result ) {
    $message = "<h4> `n  <p>Databricks job restarts for the previous hour have been detected by monitoring system. See <a href=$monitoring_dashboard_link>MONITORING DASHBOARD</a> for details.</p> `n  <p>List of restarted runs:</p> `n</h4> `n<ul>"
    if ( $jobs_restart_query_result.GetType().FullName -eq "System.Data.DataRow" ) {
        $run_id = $jobs_restart_query_result.run_id
        $job_name = $jobs_restart_query_result.job_name
        $run_link = $jobs_restart_query_result.run_link
        $current_state = $jobs_restart_query_result.life_cycle_state
        $result_state = $jobs_restart_query_result.result_state
        if($result_state -ne "")
          { $current_state = "$current_state ($result_state)" }
        $message = "$message `n  <li><a href='$run_link'>$run_id</a> - $job_name  [current_status: $current_state] </li>"
    }
    else {
        for ( $i = 0; $i -lt $jobs_restart_query_result.Length; $i++ ) {
            $run_id = $jobs_restart_query_result.run_id[$i]
            $job_name = $jobs_restart_query_result.job_name[$i]
            $run_link = $jobs_restart_query_result.run_link[$i]
            $current_state = $jobs_restart_query_result.life_cycle_state[$i]
            $result_state = $jobs_restart_query_result.result_state[$i]
            if($result_state -ne "")
              { $current_state = "$current_state ($result_state)" }
            $message = "$message `n  <li><a href='$run_link'>$run_id</a> - $job_name  [current_status: $current_state] </li>"
        }
    }
    $message = "$message `n</ul>"
    send_message $message 'jobs restart detected'
}