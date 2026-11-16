create table data_existence
(
	[table_name] [varchar](100) NULL,
	[query_responce] [varchar](10) NULL,
   	[monitoring_period_in_minutes] [int] NULL, 
	[datetime] [varchar](100) NULL
);

create table jobs_statuses
(
	[run_id] [int] NULL,
	[job_id] [int] NULL,
	[job_name] [varchar](100) NULL,
	[life_cycle_state] [varchar](100) NULL,
	[result_state] [varchar](100) NULL,
	[run_start_time] [varchar](100) NULL,
	[run_finish_time] [varchar](100) NULL,
	[datetime] [varchar](100) NULL,
	[run_link] [varchar](100) NULL,
	[run_trigger] [varchar](100) NULL	
);

create table app_credentials_expiration
(
	[app_name] [varchar](100) NULL,
	[credential_key_id] [varchar](100) NULL,
	[type] [varchar](100) NULL,
	[start_date] [varchar](100) NULL,
	[end_date] [varchar](100) NULL,
	[days_before_the_expiration] [int] NULL,
	[datetime] [varchar](100) NULL
);

create table databricks_tokens_expiration
(
	[subscription] [varchar](10) NULL,
	[environment] [varchar](10) NULL,
	[token_name] [varchar] (100) NULL,
	[token_id] [varchar](100) NULL,
	[creation_time] [varchar](100) NULL,
	[expiry_time] [varchar](100) NULL,
	[days_before_the_expiration] [int] NULL,
	[datetime] [varchar](100) NULL
);

create table sql_password_expiration
(
	[expiry_date] [varchar](10) NULL,
	[days_before_the_expiration] [int] NULL,
	[datetime] [varchar](100) NULL
);
INSERT INTO sql_password_expiration (expiry_date, days_before_the_expiration, datetime) VALUES ('2020-07-01', '', '')