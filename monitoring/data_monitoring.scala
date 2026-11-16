// required libraries: azure_sqldb_spark_1_0_2_jar_with_dependencies.jar

import com.microsoft.azure.sqldb.spark.config.Config
import com.microsoft.azure.sqldb.spark.query._
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter


val fact_monitoring_minutes = 120
val dim_monitoring_minutes = 120


def get_status_fact( fact_name:String, fact_monitoring_minutes:Int ) {
  val refresh_query = s"refresh table prepared.${fact_name}"
  spark.sql(refresh_query)
  val df_query = s"""
      select 
        if(count(*) > 0, 1, 0 ) as ${fact_name}_status
      from prepared.${fact_name}
      where year = year(from_unixtime(unix_timestamp(current_timestamp))) 
        and week_number = weekofyear(from_unixtime(unix_timestamp(current_timestamp))) 
        and unix_timestamp(persisted_date_utc) >= unix_timestamp(current_timestamp) - ${fact_monitoring_minutes} * 60
  """
  val df = spark.sql(df_query)
  val status_value = df.head().getInt(0)
  send_status_to_database( fact_name, status_value, fact_monitoring_minutes )
}

def get_status_dim( dim_name:String, dim_monitoring_minutes:Int ) {
  val refresh_query = s"refresh table prepared.${dim_name}"
  spark.sql(refresh_query)
  val df_query = s"""
      select 
        if(count(*) > 0, 1, 0 ) as ${dim_name}_status
      from prepared.${dim_name}
      where unix_timestamp(persisted_date_utc) >= unix_timestamp(current_timestamp) - ${dim_monitoring_minutes} * 60
  """
  val df = spark.sql(df_query)
  val status_value = df.head().getInt(0)
  send_status_to_database( dim_name, status_value, dim_monitoring_minutes )
}

def send_status_to_database( name:String, status_value:Int, monitoring_period:Int ) {
  val timestamp = LocalDateTime.now()
  val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss")
  val datetime = formatter.format(timestamp)
  val sql_pass = sys.env("SQL_PASS")
  val query = s"INSERT INTO data_existence (table_name, query_responce, monitoring_period_in_minutes, datetime) VALUES ('$name', $status_value, $monitoring_period, '$datetime');"
  val config = Config(Map(
    "url"          -> "mvsdatalake${SUBSCRIPTION}${ENV}tco1.database.windows.net",
    "databaseName" -> "mvsdatalake-${SUBSCRIPTION}${ENV}-monitoring-tco",
    "user"         -> "sqladmin",
    "password"     -> sql_pass,
    "queryCustom"  -> query
  ))
  sqlContext.sqlDBQuery(config)
}


get_status_fact( "fact_trip", fact_monitoring_minutes )
get_status_fact( "fact_subtrip", fact_monitoring_minutes )
get_status_fact( "fact_position", fact_monitoring_minutes )
get_status_fact( "fact_event", fact_monitoring_minutes )

get_status_dim( "dim_driver", dim_monitoring_minutes )
get_status_dim( "dim_vehicle", dim_monitoring_minutes )
get_status_dim( "dim_event_description", dim_monitoring_minutes )
// get_status_dim( "dim_location", dim_monitoring_minutes )