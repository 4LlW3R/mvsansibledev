#!/bin/bash
set -x

service_cl_json='''{
  "cluster_name": "monitoring-cluster",
  "spark_version": "5.5.x-scala2.11",
  "node_type_id": "Standard_F4s",
  "driver_node_type_id": "Standard_F4s",
  "cluster_log_conf": {
      "dbfs": {
          "destination":"dbfs:/mnt/logs/cluster-logs/'$DBSPROFILE'"
      }
  },
  "init_scripts": [ {
    "dbfs": {
      "destination": "dbfs:/databricks/scripts/init-'$DBSPROFILE'.sh"
    }
  } ],
"spark_env_vars": {
    "SQL_PASS": "'$SQL_PASS'"
},
  "autotermination_minutes": 120,
  "num_workers": 1
}'''

response_create=$(databricks clusters create --profile "$DBSPROFILE" --json "$service_cl_json")
service_cl_id=$(echo "$response_create" | jq -r .cluster_id)

status=$(databricks clusters get --profile "$DBSPROFILE" --cluster-id "$service_cl_id" | jq -r .state)
while [[ $status != "RUNNING" ]]; do
  if [ $status == "ERROR" ] || [ $status == "TERMINATED" ]; then
    echo "Cluster state: $status"
    exit 1
  fi
  echo "Cluster state: $status"
  sleep 30
  status=$(databricks clusters get --profile "$DBSPROFILE" --cluster-id "$service_cl_id" | jq -r .state)
done
echo "Cluster was created. Cluster ID: $service_cl_id"

databricks libraries install --profile "$DBSPROFILE" --cluster-id "$service_cl_id" --maven-coordinates 'com.microsoft.azure:azure-sqldb-spark:1.0.2' --maven-repo 'https://repo1.maven.org/maven2'
sleep 3m
echo "azure-sqldb-spark library has been installed"


envsubst '$ENV $SUBSCRIPTION' < $BUILD_SOURCESDIRECTORY/monitoring/data_monitoring.scala > monitoring_notebook.scala
databricks workspace import --profile "$DBSPROFILE" --language SCALA --format SOURCE --overwrite  "monitoring_notebook.scala" "/Users/konstantin_farvazov@epam.com/monitoring_notebook.scala"
echo "Notebook was uploaded. Notebok path: /Users/konstantin_farvazov@epam.com/monitoring_notebook.scala"

monitoring_job_json='''{
  "name": "DataMonitoring",
  "existing_cluster_id": "'$service_cl_id'",
  "notebook_task": {
    "notebook_path": "/Users/konstantin_farvazov@epam.com/monitoring_notebook.scala"
  },
  "schedule": {
    "quartz_cron_expression": "0 0/30 * * * ?",
    "timezone_id": "UTC"
  }
}'''

response_job=$(databricks jobs create --profile "$DBSPROFILE" --json "$monitoring_job_json")
job_id=$( echo "$response_job" | jq -r .job_id)
echo "DataMonitoring job has been created. Job ID: $job_id"

response_run=$(databricks jobs run-now --profile "$DBSPROFILE" --job-id "$job_id")
run_id=$(echo "$response_run" | jq .run_id)

while true; do
  run_status="$(databricks runs get --profile "$DBSPROFILE" --run-id $run_id | jq -r '.state.result_state')"
  if [ $run_status == "SUCCESS" ]; then
    echo "Run status is $run_status"
    break
  fi
  if [ $run_status == "FAILED" ] || [ $run_status == "TIMEDOUT" ] || [ $run_status == "CANCELED" ]; then
    echo "Run status is $run_status"
    exit 1
  fi
  echo "DataMonitoring is running"
  sleep 10
done

echo "First run of DataMonitoring job sucessfully finished"