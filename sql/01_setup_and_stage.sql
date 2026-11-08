-- ===============================================================
-- 01_setup_and_stage.sql
-- Creates the database and the raw staging table, then loads the CSV into it.
-- Before running: edit the CSV path below. The file must be readable by the
-- SQL Server service (e.g. C:\Temp\).
-- The CSV uses NZ-style dd/mm/yyyy dates; the clean step converts them
-- explicitly with style 103.
-- Rerunning wipes and reloads the staging table.
-- Next: run 02_clean_and_load.sql.
-- ===============================================================

IF DB_ID('TenantMaintenance') IS NULL CREATE DATABASE TenantMaintenance;
GO
USE TenantMaintenance;
GO

DROP TABLE IF EXISTS requests;
DROP TABLE IF EXISTS statuses;
DROP TABLE IF EXISTS contractors;
DROP TABLE IF EXISTS properties;
DROP TABLE IF EXISTS dbo.requests_raw;

CREATE TABLE dbo.requests_raw ( 
	Id NVARCHAR(20), Start_Time NVARCHAR(50), Completion_time NVARCHAR(50), Tenant_Address NVARCHAR(100), Issue_Category NVARCHAR(50), Urgency NVARCHAR(20),
	Description NVARCHAR(300), Date_Noticed NVARCHAR(50), Contact_Preference NVARCHAR(20), 
	Satisfaction NVARCHAR(10), Status NVARCHAR(30), Date_Resolved NVARCHAR(50),
	Cost_NZD NVARCHAR(20), Contractor NVARCHAR(100)
);


BULK INSERT dbo.requests_raw
FROM 'C:\Temp\Tenant_Request_Raw_Data.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,          -- skip the header row
    FIELDQUOTE = '"',
    CODEPAGE = '65001'     -- UTF-8
);
SELECT COUNT(*) AS raw_rows FROM dbo.requests_raw;   -- expect 158