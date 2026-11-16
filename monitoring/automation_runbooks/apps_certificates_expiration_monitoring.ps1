# required modules: Az.Accounts; Az.KeyVault; SqlServer
# required credentials: SP-MvsDatalakeProd-credential; SP-MvsDatalakeTest-credential; SP-MvsProdTco-credential

$tenant = Get-AutomationVariable -Name "tenant"
$subscription = Get-AutomationVariable -Name "subscription"
$env = Get-AutomationVariable -Name "env"
$sql_user =  Get-AutomationVariable -Name "sql_user"

$sql_server = "mvsdatalake${subscription}${env}tco1.database.windows.net"
$sql_db = "mvsdatalake-${subscription}${env}-monitoring-tco"
$table_name = 'app_credentials_expiration'

$applist = @("dc6e9246-9173-4373-8633-0bd762a44944", `    # 'Mvsdatalake - Test'
             "5e8827db-cb69-4300-9faa-563603e3b3a2", `    # 'Mvsdatalake - Prod'
             "94769b5c-2527-49d9-83a0-158c1059852a", `    # 'spMvsProdTco'
             "f6e9b7df-2c99-4947-9113-4127be1a7f25")      # 'epam.test.serviceprincipal'

if ($subscription -eq "p332")
  { $SPcred = Get-AutomationPSCredential -Name 'SP-MvsDatalakeProd-credential' }
else
  { $SPcred = Get-AutomationPSCredential -Name 'SP-MvsDatalakeTest-credential' }
$app_id = $SPcred.UserName
$app_secret = $SPcred.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $app_id, $app_secret
Connect-AzAccount -Credential $Credential -Tenant "$tenant" -ServicePrincipal
$sql_pass = (Get-AzKeyVaultSecret -VaultName "tco-mvs-${subscription}${env}-kv" -Name "$sql_user").SecretValueText
Disconnect-AzAccount

$SPcred = Get-AutomationPSCredential -Name 'SP-MvsProdTco-credential'
$app_id = $SPcred.UserName
$app_secret = $SPcred.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $app_id, $app_secret
Connect-AzAccount -Credential $Credential -Tenant "$tenant" -ServicePrincipal



foreach ($app in $applist) {
    $application = Get-AzADApplication -ObjectId $app
    $app_name = $application.DisplayName

    $cert_list = Get-AzADAppCredential -ObjectId $app
    foreach ($cert in $cert_list) {
        $credential_key_id = $cert.KeyId
        $type = $cert.Type  
        $start_date = $cert.StartDate
        $end_date = $cert.EndDate
        $datetime = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        $days_before_the_expiration = (New-TimeSpan -Start $datetime -End $end_date).Days
  
        $query = "
          IF EXISTS(SELECT * FROM $table_name WHERE credential_key_id='$credential_key_id')
            UPDATE $table_name SET app_name='$app_name', credential_key_id='$credential_key_id', type='$type', start_date='$start_date', end_date='$end_date', days_before_the_expiration='$days_before_the_expiration', datetime='$datetime'
            WHERE credential_key_id='$credential_key_id'
          ELSE
            INSERT INTO $table_name 
              (app_name, credential_key_id, type, start_date, end_date, days_before_the_expiration, datetime) 
            VALUES 
              ('$app_name', '$credential_key_id', '$type', '$start_date', '$end_date', '$days_before_the_expiration', '$datetime');
        "
        
        Invoke-SqlCmd -ServerInstance $sql_server -Database $sql_db -Username $sql_user -Password $sql_pass -query $query
    }
}