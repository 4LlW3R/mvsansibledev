# required modules: Az.Accounts; Az.KeyVault; SqlServer; azure.databricks.cicd.tools
# required credentials: SP-MvsDatalakeProd-credential; SP-MvsDatalakeTest-credential

$tenant = Get-AutomationVariable -Name "tenant"
$subscription = Get-AutomationVariable -Name "subscription"
$env = Get-AutomationVariable -Name "env"
$sql_user =  Get-AutomationVariable -Name "sql_user"

$sql_server = "mvsdatalake${subscription}${env}tco1.database.windows.net"
$sql_db = "mvsdatalake-${subscription}${env}-monitoring-tco"
$table_name = 'databricks_tokens_expiration'

$SPcred = Get-AutomationPSCredential -Name 'SP-MvsDatalakeProd-credential'
$app_id = $SPcred.UserName
$app_secret = $SPcred.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $app_id, $app_secret
Connect-AzAccount -Credential $Credential -Tenant "$tenant" -ServicePrincipal
$databrickscfg_p332_base64 = (Get-AzKeyVaultSecret -VaultName 'mvsdatalake-p332-cvx' -Name 'databrickscfg').SecretValueText
Disconnect-AzAccount
$SPcred = Get-AutomationPSCredential -Name 'SP-MvsDatalakeTest-credential'
$app_id = $SPcred.UserName
$app_secret = $SPcred.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $app_id, $app_secret
Connect-AzAccount -Credential $Credential -Tenant "$tenant" -ServicePrincipal
$databrickscfg_t332_base64 = (Get-AzKeyVaultSecret -VaultName 'mvsdatalake-t332-cvx' -Name 'databrickscfg').SecretValueText
Disconnect-AzAccount

if ($subscription -eq "p332")
  { $SPcred = Get-AutomationPSCredential -Name 'SP-MvsDatalakeProd-credential' }
else
  { $SPcred = Get-AutomationPSCredential -Name 'SP-MvsDatalakeTest-credential' }
$app_id = $SPcred.UserName
$app_secret = $SPcred.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $app_id, $app_secret
Connect-AzAccount -Credential $Credential -Tenant "$tenant" -ServicePrincipal
$sql_pass = (Get-AzKeyVaultSecret -VaultName "tco-mvs-${subscription}${env}-kv" -Name "$sql_user").SecretValueText



$EpochStart = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0

$databrickscfg_p332 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($databrickscfg_p332_base64))
Out-File -FilePath combined_databrickscfg.txt -InputObject $databrickscfg_p332

$databrickscfg_t332 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($databrickscfg_t332_base64))
Out-File -FilePath combined_databrickscfg.txt -InputObject $databrickscfg_t332 -Append

$sub_envs_list = (Get-Content combined_databrickscfg.txt | Select-String -Pattern "\[.*\]" | Select-Object -Unique)
$sub_envs = ($sub_envs_list -replace "\[" -replace "\]")

$tokens_list = (Get-Content combined_databrickscfg.txt | Select-String -Pattern "^token" | Select-Object -Unique)
$tokens = ($tokens_list -replace ".*= ")



# legacy prod environment:
$sub = 'p80kz'
$env = $sub_envs[0]
$token = $tokens[0]
Connect-Databricks -BearerToken $token -Region northeurope
$token_information = (Get-DatabricksBearerToken -BearerToken $token -Region northeurope).token_infos

$token_name = $token_information.comment 
$token_id = $token_information.token_id
$creation_time = Get-Date $EpochStart.AddMilliseconds($token_information.creation_time) -Format "yyyy-MM-ddTHH:mm:ss"
$expiry_time = Get-Date $EpochStart.AddMilliseconds($token_information.expiry_time) -Format "yyyy-MM-ddTHH:mm:ss"
$datetime = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
$days_before_the_expiration = (New-TimeSpan -Start $datetime -End $expiry_time).Days

$query = "
  IF EXISTS(SELECT * FROM $table_name WHERE token_id='$token_id')
    UPDATE $table_name SET subscription='$sub', environment='$env', token_name='$token_name', token_id='$token_id', creation_time='$creation_time', expiry_time='$expiry_time', days_before_the_expiration='$days_before_the_expiration', datetime='$datetime'
    WHERE token_id='$token_id'
  ELSE
    INSERT INTO $table_name 
      (subscription, environment, token_name, token_id, creation_time, expiry_time, days_before_the_expiration, datetime) 
    VALUES 
      ('$sub', '$env', '$token_name', '$token_id', '$creation_time', '$expiry_time', '$days_before_the_expiration', '$datetime') ;
"

Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $query



# new API environments:
for ( $i = 1; $i -lt $tokens.length; $i++ ) {
    $sub = $sub_envs[$i].substring(0,4)
    $env = $sub_envs[$i].substring(4)
    $token = $tokens[$i]
    Connect-Databricks -BearerToken $token -Region westeurope
    $token_information = (Get-DatabricksBearerToken -BearerToken $token -Region westeurope).token_infos

    $token_name = $token_information.comment 
    $token_id = $token_information.token_id
    $creation_time = Get-Date $EpochStart.AddMilliseconds($token_information.creation_time) -Format "yyyy-MM-ddTHH:mm:ss"
    $expiry_time = Get-Date $EpochStart.AddMilliseconds($token_information.expiry_time) -Format "yyyy-MM-ddTHH:mm:ss"
    $datetime = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    $days_before_the_expiration = (New-TimeSpan -Start $datetime -End $expiry_time).Days

    $query = "
      IF EXISTS(SELECT * FROM $table_name WHERE token_id='$token_id')
        UPDATE $table_name SET subscription='$sub', environment='$env', token_name='$token_name', token_id='$token_id', creation_time='$creation_time', expiry_time='$expiry_time', days_before_the_expiration='$days_before_the_expiration', datetime='$datetime'
        WHERE token_id='$token_id'
      ELSE
        INSERT INTO $table_name 
          (subscription, environment, token_name, token_id, creation_time, expiry_time, days_before_the_expiration, datetime) 
        VALUES 
          ('$sub', '$env', '$token_name', '$token_id', '$creation_time', '$expiry_time', '$days_before_the_expiration', '$datetime') ;
    "
    
    Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $query
}