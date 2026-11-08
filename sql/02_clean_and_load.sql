-- ===============================================================
-- 02_clean_and_load.sql
-- Builds the clean schema from dbo.requests_raw. Run after 01. Safe to rerun.
-- ===============================================================
USE TenantMaintenance;
GO

DROP TABLE IF EXISTS requests;
DROP TABLE IF EXISTS statuses;
DROP TABLE IF EXISTS contractors;
DROP TABLE IF EXISTS properties;

-- Create Clean Tables
CREATE TABLE properties (
	property_id INT Identity (1,1) PRIMARY KEY,
	address NVARCHAR(100) NOT NULL UNIQUE
);
INSERT INTO properties (address)
VALUES ('3 Bond Street'), ('22 West Close'), ('5 North End');

CREATE TABLE contractors (
	contractor_id INT IDENTITY(1,1) PRIMARY KEY,
	contractor_name NVARCHAR(100) NOT NULL UNIQUE
);
INSERT INTO contractors (contractor_name)
SELECT DISTINCT TRIM(Contractor) FROM requests_raw
WHERE NULLIF(TRIM(Contractor), '') IS NOT NULL;

CREATE TABLE statuses (
	status_id INT PRIMARY KEY,
	status_name NVARCHAR(30) NOT NULL UNIQUE
);
INSERT INTO statuses VALUES
(1,'Reported'),(2,'Tenant Contacted'),(3,'Contractor Booked'),
(4,'Work In Progress'),(5,'Resolved');

CREATE TABLE requests (
	request_id INT PRIMARY KEY,
	property_id INT NOT NULL REFERENCES properties(property_id),
	contractor_id INT NULL REFERENCES contractors(contractor_id),
	status_id INT NOT NULL REFERENCES statuses(status_id),
	issue_category NVARCHAR(50), urgency NVARCHAR(20),
	description NVARCHAR(300), contact_preference NVARCHAR(20),
	submitted_at DATETIME2, date_noticed DATE, date_resolved DATE,
	satisfaction TINYINT NULL, cost_nzd DECIMAL (10,2) NULL
);

--  Clean and Load
WITH cleaned AS (
	SELECT
		TRY_CONVERT(INT, Id) AS request_id,
		TRY_CONVERT(DATETIME2, Start_time, 103) AS submitted_at,

-- Standardise the 12 variants of Address Entries down to 3 
		CASE	WHEN UPPER(Tenant_Address) LIKE '%BOND%' THEN '3 Bond Street'
				WHEN UPPER(Tenant_Address) LIKE '%WEST%' 
				OR UPPER(Tenant_Address) LIKE '%WSET%' THEN '22 West Close'
				WHEN UPPER(Tenant_Address) LIKE '%N%END%' THEN '5 North End'
		END AS address,

		TRIM(Issue_Category) AS issue_category,
		TRIM(Urgency) AS urgency,
		TRIM(Description) AS description,
		TRIM(Contact_Preference) AS contact_preference,
		COALESCE(TRY_CONVERT(DATE, NULLIF(Date_Noticed, ''), 103),
			CAST(TRY_CONVERT(DATETIME2, Start_time, 103) AS DATE)) AS date_noticed,
		TRY_CONVERT(DATE, NULLIF(Date_Resolved, ''), 103) AS date_resolved,
		TRY_CONVERT(TINYINT, NULLIF(Satisfaction, '')) AS satisfaction,
		TRY_CONVERT(DECIMAL(10,2), REPLACE(NULLIF(Cost_NZD, ''), ',', '')) AS cost_nzd,
		TRIM(Status) AS status,
		TRIM(Contractor) AS contractor
	FROM requests_raw
),

-- Flag duplicate submissions: keep the earliest of each (rn = 1)
ranked AS (
	SELECT *, ROW_NUMBER() OVER (
		PARTITION BY address, issue_category, description, date_noticed
		ORDER BY request_id) AS rn
	FROM cleaned
)

-- Load only the first of each duplicate group, joined to the lookup tables
INSERT INTO requests (request_id, property_id, contractor_id, status_id,
			issue_category, urgency, description, contact_preference,
			submitted_at, date_noticed, date_resolved, satisfaction, cost_nzd)

SELECT	r.request_id, p.property_id, k.contractor_id, s.status_id,
		r.issue_category, r.urgency, r.description, r.contact_preference,
		r.submitted_at, r.date_noticed, r.date_resolved, r.satisfaction, r.cost_nzd
FROM ranked r
JOIN properties p ON p.address = r.address
JOIN statuses s ON s.status_name = r.status
LEFT JOIN contractors k ON k.contractor_name = r.contractor
WHERE r.rn = 1;

-- Sanity checks
SELECT COUNT(*) AS raw_rows FROM requests_raw;     -- expect 158
SELECT COUNT(*) AS clean_rows FROM requests;       -- expect 154

-- Rows that didn't load: should be exactly the 4 duplicates (Ids 21, 36, 43, 91)
SELECT Id, Tenant_Address, Description
FROM requests_raw
WHERE TRY_CONVERT(INT, Id) NOT IN (SELECT request_id FROM requests);

-- Should return 0: no date should be missing or fall back to 1900
SELECT COUNT(*) AS bad_dates FROM requests
WHERE date_noticed IS NULL OR date_noticed < '2026-01-01';

-- Id 24 had no Date_Noticed in the source: should show its submission date (2026-02-25)
SELECT request_id, date_noticed FROM requests WHERE request_id = 24;

-- Should return 0: every resolved job should have a cost
SELECT COUNT(*) AS resolved_without_cost
FROM requests WHERE date_resolved IS NOT NULL AND cost_nzd IS NULL;