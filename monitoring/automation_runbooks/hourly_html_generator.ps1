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

if ($subscription -eq "p332")
  { $SPcred = Get-AutomationPSCredential -Name 'SP-MvsDatalakeProd-credential' }
else
  { $SPcred = Get-AutomationPSCredential -Name 'SP-MvsDatalakeTest-credential' }
$app_id = $SPcred.UserName
$app_secret = $SPcred.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $app_id, $app_secret
Connect-AzAccount -Credential $Credential -Tenant "$tenant" -ServicePrincipal
$sql_pass = (Get-AzKeyVaultSecret -VaultName "tco-mvs-${subscription}${env}-kv" -Name "$sql_user").SecretValueText



Function job_statuses_color_definition ($run_life_cycle_state, $run_result_state) {
    $color = ''
    if(($run_life_cycle_state -eq "RUNNING") -OR ($run_life_cycle_state -eq "PENDING"))
      { $color = "color:blue" }
    if(($run_life_cycle_state -eq "INTERNAL_ERROR") -OR ($run_result_state -eq "FAILED") -OR ($run_result_state -eq "TIMEDOUT"))
      { $color = "color:red" }
    if(($run_life_cycle_state -eq "SKIPPED") -OR ($run_result_state -eq "CANCELED"))
      { $color = "color:grey" }
    if($run_result_state -eq "SUCCESS")
      { $color = "color:green" }
    return $color
}

Function job_statuses_table_raw_generation ($job_name, $successfully_terminated_runs_percentage, $run_id, $run_life_cycle_state, $run_result_state, $run_start_time, $run_finish_time, $run_record_datetime, $run_link) {
    $raw_color = job_statuses_color_definition $run_life_cycle_state $run_result_state
    $link_separator = $run_link.IndexOf("/run/")
    $job_link = $run_link.Substring(0, $link_separator)
    $raw = "
        <tr style=font-weight:bold;$raw_color>
          <td><a href='$job_link' style='$raw_color'>$job_name</a></td>
          <td>$successfully_terminated_runs_percentage</td>
          <td><a href='$run_link' style='$raw_color'>$run_id</a></td>
          <td>$run_life_cycle_state</td>
          <td>$run_result_state</td>
          <td>$run_start_time</td>
          <td>$run_finish_time</td>
          <td>$run_record_datetime</td>
        </tr>
    "
    Out-File -FilePath index.html -InputObject $raw -Append
}

Function data_existence_color_definition ($table_query_responce) {
    $color = ''
    if($table_query_responce -eq "1")
      { $color = "color:green" }
    if($table_query_responce -eq "0")
      { $color = "color:red" }
    return $color
}

Function data_existence_raw_generation ($table_name, $successfull_queries_percentage, $table_query_responce, $table_monitoring_period, $table_record_datetime) {
    $raw_color = data_existence_color_definition $table_query_responce
    $raw = "
        <tr style=font-weight:bold;$raw_color>
          <td>$table_name</td>
          <td>$successfull_queries_percentage</td>
          <td>$table_query_responce</td>
          <td>$table_monitoring_period</td>
          <td>$table_record_datetime</td>
        </tr>
    "
    Out-File -FilePath index.html -InputObject $raw -Append
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
          <li><a class='active' href='index.html'>${subscription}${env} Databricks jobs statuses and data availability information</a></li>
          <li><a href='second.html'>Expiration information</a></li>
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
Out-File -FilePath index.html -InputObject $page_header



$jobs_count = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query "SELECT COUNT(DISTINCT job_id) AS number FROM jobs_statuses").number

$jobs_statuses_query = "
    SELECT q1.job_name, q1.last_run_id, q1.life_cycle_state, q1.result_state, q1.run_start_time, q1.run_finish_time, q1.datetime, q1.run_link,
	       CASE  WHEN (q2.successful_runs IS NULL) AND (q2.all_runs IS NOT NULL)
			     THEN 0
			     ELSE ROUND(CAST(q2.successful_runs AS REAL)/CAST(q2.all_runs AS REAL), 3)*100
			     END 
			     AS successfully_terminated_runs_percentage
    FROM
    (
      SELECT t1.job_id, t1.job_name, t1.life_cycle_state, t1.result_state, t1.run_start_time, t1.run_finish_time, t1.datetime, t1.run_link, t2.last_run_id
      FROM jobs_statuses t1
      INNER JOIN
      (
        SELECT job_id, MAX(run_id) AS last_run_id
        FROM jobs_statuses
        GROUP BY job_id
      ) t2
      ON t1.job_id = t2.job_id AND t1.run_id = t2.last_run_id
    ) q1
    LEFT JOIN
    (
      SELECT p1.job_id, p1.all_runs, p2.successful_runs
      FROM
      (
        SELECT job_id, COUNT(run_id) as all_runs
        FROM jobs_statuses
        WHERE ((life_cycle_state='TERMINATED' AND result_state<>'CANCELED') OR life_cycle_state='INTERNAL_ERROR') AND DATEDIFF(day, CAST(run_finish_time AS datetime), CURRENT_TIMESTAMP) < 3
        GROUP BY job_id
      ) p1
      LEFT JOIN
      (
        SELECT job_id, COUNT(run_id) as successful_runs
        FROM jobs_statuses
        WHERE life_cycle_state='TERMINATED' AND result_state='SUCCESS' AND DATEDIFF(day, CAST(run_finish_time AS datetime), CURRENT_TIMESTAMP) < 3
        GROUP BY job_id
      ) p2
      ON p1.job_id = p2.job_id
    ) q2
    ON q1.job_id = q2.job_id
    ORDER BY q1.job_name
"
$job_statuses_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $jobs_statuses_query)

$job_statuses_table_header = "
    <td> 
      <table border=3 cellpadding=3>
      <caption style=font-weight:bold;font-size:200%>Databricks jobs statuses</caption>
        <tr style=font-weight:bold;font-size:125%;text-align:center;vertical-align:middle> 
          <td>Job name</td>
          <td>Percentage of<br>successful runs<br>for last 3 days</td>
          <td>Last run<br>ID</td>
          <td>Last run<br>life cycle state</td>
          <td>Last run<br>result state</td>
          <td>Last run<br>start time (UTC)</td>
          <td>Last run<br>finish time (UTC)</td>
          <td>DateTime of record<br>update in database (UTC)</td>
        </tr>
"
Out-File -FilePath index.html -InputObject $job_statuses_table_header -Append

for ( $i = 0; $i -lt $jobs_count; $i++ ) {
    if($job_statuses_query_result.job_name[$i] -ne "${subscription}${env}-Provision-job") { 
        job_statuses_table_raw_generation $job_statuses_query_result.job_name[$i] `
                                          $job_statuses_query_result.successfully_terminated_runs_percentage[$i] `
                                          $job_statuses_query_result.last_run_id[$i] `
                                          $job_statuses_query_result.life_cycle_state[$i] `
                                          $job_statuses_query_result.result_state[$i] `
                                          $job_statuses_query_result.run_start_time[$i] `
                                          $job_statuses_query_result.run_finish_time[$i] `
                                          $job_statuses_query_result.datetime[$i] `
                                          $job_statuses_query_result.run_link[$i]                                       
    }
}

$job_statuses_table_ending = "</table> </td>"
Out-File -FilePath index.html -InputObject $job_statuses_table_ending -Append



$tables_count = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query "SELECT COUNT(DISTINCT table_name) AS number FROM data_existence").number

$data_existence_query = "
    SELECT q1.table_name, q1.query_responce, q1.monitoring_period_in_minutes, q1.datetime, ROUND(CAST(q2.successful_queries AS REAL)/CAST(q2.all_queries AS REAL), 3)*100 AS successfull_queries_percentage
    FROM
    (
      SELECT t1.table_name, t1.query_responce, t1.monitoring_period_in_minutes, t1.datetime
      FROM data_existence t1
      INNER JOIN
      (
        SELECT table_name, MAX(datetime) AS max_datetime
        FROM data_existence
        GROUP BY table_name
      ) t2
      ON t1.table_name = t2.table_name AND t1.datetime = t2.max_datetime
    ) q1
    LEFT JOIN
    (
      SELECT p1.table_name, p1.all_queries, p2.successful_queries
      FROM
      (
        SELECT table_name, COUNT(query_responce) as all_queries
        FROM data_existence
		WHERE DATEDIFF(day, CAST(datetime AS datetime), CURRENT_TIMESTAMP) < 3
        GROUP BY table_name
      ) p1
      LEFT JOIN
      (
        SELECT table_name, COUNT(query_responce) as successful_queries
        FROM data_existence
        WHERE query_responce=1 AND DATEDIFF(day, CAST(datetime AS datetime), CURRENT_TIMESTAMP) < 3
        GROUP BY table_name
      ) p2
      ON p1.table_name = p2.table_name
    ) q2
    ON q1.table_name = q2.table_name
"
$data_existence_query_result = (Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $data_existence_query)

$data_existence_table_header = "
    <td> 
      <table border=3 cellpadding=3>
      <caption style=font-weight:bold;font-size:200%>Data availability</caption>
        <tr style=font-weight:bold;font-size:125%;text-align:center;vertical-align:middle>
          <td>Data Lake<br>table name</td>
          <td>Percentage of<br>successful queries<br>for last 3 days</td>
          <td>Last result of<br>data existence query</td>
          <td>Last monitoring<br>period in minutes</td>
          <td>DateTime of record<br>update in database (UTC)</td>
        </tr>
"
Out-File -FilePath index.html -InputObject $data_existence_table_header -Append

for ( $i = 0; $i -lt $tables_count; $i++ ) {
    data_existence_raw_generation $data_existence_query_result.table_name[$i] `
                                  $data_existence_query_result.successfull_queries_percentage[$i] `
                                  $data_existence_query_result.query_responce[$i] `
                                  $data_existence_query_result.monitoring_period_in_minutes[$i] `
                                  $data_existence_query_result.datetime[$i]
}

$data_existence_table_ending = "</table> </td>"
Out-File -FilePath index.html -InputObject $data_existence_table_ending -Append



$page_ending = "</tr> </table> </body> </html>"
Out-File -FilePath index.html -InputObject $page_ending -Append



$ftp_password = ConvertTo-SecureString $ftp_pass -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential($ftp_user,$ftp_password)
Set-FTPConnection -Credentials $creds -Server $ftp_server -Session FTPsession -UsePassive 
$Session = Get-FTPConnection -Session FTPsession 
Add-FTPItem -Session $Session -Path /site/wwwroot/ -LocalPath index.html -Overwrite