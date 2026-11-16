# required modules: Az.Accounts; Az.KeyVault; SqlServer; azure.databricks.cicd.tools
# required credentials: SP-MvsDatalakeProd-credential; SP-MvsDatalakeTest-credential

$tenant = Get-AutomationVariable -Name "tenant"
$subscription = Get-AutomationVariable -Name "subscription"
$env = Get-AutomationVariable -Name "env"
$sql_user =  Get-AutomationVariable -Name "sql_user"

$sql_server = "mvsdatalake${subscription}${env}tco1.database.windows.net"
$sql_db = "mvsdatalake-${subscription}${env}-monitoring-tco"
$table_name = 'jobs_statuses'

if ($subscription -eq "p332")
  { $SPcred = Get-AutomationPSCredential -Name 'SP-MvsDatalakeProd-credential' }
else
  { $SPcred = Get-AutomationPSCredential -Name 'SP-MvsDatalakeTest-credential' }
$app_id = $SPcred.UserName
$app_secret = $SPcred.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $app_id, $app_secret
Connect-AzAccount -Credential $Credential -Tenant "$tenant" -ServicePrincipal
$sql_pass = (Get-AzKeyVaultSecret -VaultName "tco-mvs-${subscription}${env}-kv" -Name "$sql_user").SecretValueText
$token = (Get-AzKeyVaultSecret -VaultName "tco-mvs-${subscription}${env}-kv" -Name 'databricks-accesstoken').SecretValueText



$EpochStart = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0

Connect-Databricks -BearerToken $token -Region westeurope

$jobs_ids = (Get-DatabricksJobs -BearerToken $token -Region westeurope).job_id

foreach($job in $jobs_ids) {
    $ten_last_runs = (Get-DatabricksJobRunList -BearerToken $token -Region westeurope -JobId $job).runs[9..0]

    foreach($run in $ten_last_runs) {
        $run_id = $run.run_id
        $job_id = $run.job_id
        $job_name = $run.run_name
        $run_life_cycle_state = $run.state.life_cycle_state
        $run_result_state = $run.state.result_state
        $run_link = $run.run_page_url
        $run_trigger = $run.trigger
        $datetime = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")

        $epoch_run_start_time = $run.start_time
        $run_start_time = Get-Date $EpochStart.AddMilliseconds($epoch_run_start_time) -Format "yyyy-MM-ddTHH:mm:ss"

        $run_finish_time = ''
        if(($run_life_cycle_state -eq "TERMINATED") -OR ($run_life_cycle_state -eq "INTERNAL_ERROR")) {
            $epoch_run_finish_time = $run.start_time + $run.setup_duration + $run.execution_duration + $run.cleanup_duration
            $run_finish_time = Get-Date $EpochStart.AddMilliseconds($epoch_run_finish_time) -Format "yyyy-MM-ddTHH:mm:ss"
        }

        $query = "
          IF EXISTS(SELECT * FROM $table_name WHERE run_id=$run_id)
            UPDATE $table_name SET life_cycle_state='$run_life_cycle_state', result_state='$run_result_state', run_start_time='$run_start_time', run_finish_time='$run_finish_time', datetime='$datetime', run_link='$run_link', run_trigger='$run_trigger'
            WHERE run_id=$run_id
          ELSE
            INSERT INTO $table_name 
              (run_id, job_id, job_name, life_cycle_state, result_state, run_start_time, run_finish_time, datetime, run_link, run_trigger) 
            VALUES 
              ('$run_id', '$job_id', '$job_name', '$run_life_cycle_state', '$run_result_state', '$run_start_time', '$run_finish_time', '$datetime', '$run_link', '$run_trigger');
        "
    
        Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $query
    }
}