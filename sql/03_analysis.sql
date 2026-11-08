-- ============================================================
-- 03_analysis.sql
-- Analysis queries on the cleaned data. Run after 02.
-- ============================================================
USE TenantMaintenance;
GO

-- 1. Which types of fault take longest to resolve, and which cost the most?
SELECT issue_category,
       COUNT(*) AS resolved_requests,
       ROUND(AVG(DATEDIFF(DAY, date_noticed, date_resolved)* 1.0), 1) AS avg_days_to_resolve,
       SUM(cost_nzd) AS total_cost
FROM requests
WHERE date_resolved IS NOT NULL
GROUP BY issue_category
ORDER BY avg_days_to_resolve DESC;

-- 2. Which property generates the most requests and spend?
-- Note: request counts include the 7 open requests. Costs don't, as open jobs have no cost yet.
SELECT p.address,
       COUNT(*) AS requests,
       SUM(r.cost_nzd) AS total_cost,
       ROUND(AVG(r.cost_nzd), 2) AS avg_cost
FROM requests r
JOIN properties p ON p.property_id = r.property_id
GROUP BY p.address
ORDER BY total_cost DESC;

-- 3. Contractor performance, overall
-- NAIVE VIEW: ignores that contractors do different types of work, so a contractor
-- handling mostly slow jobs (garden, odd jobs) looks slow. See query 5 for the
-- like-for-like comparison within each category.
SELECT k.contractor_name,
       COUNT(*) AS jobs,
       ROUND(AVG(DATEDIFF(DAY, r.date_noticed, r.date_resolved) * 1.0), 1) AS avg_days,
       ROUND(AVG(r.cost_nzd), 2) AS avg_cost,
       COUNT(r.satisfaction) AS ratings_given,
       ROUND(AVG(CAST(r.satisfaction AS DECIMAL(3,1))), 1) AS avg_satisfaction
FROM requests r
JOIN contractors k ON k.contractor_id = r.contractor_id
WHERE r.date_resolved IS NOT NULL
GROUP BY k.contractor_name
ORDER BY avg_days;

-- 4. Is resolution speed driven by urgency?
SELECT urgency,
       COUNT(*) AS resolved_requests,
       ROUND(AVG(DATEDIFF(DAY, date_noticed, date_resolved) * 1.0), 1) AS avg_days
FROM requests
WHERE date_resolved IS NOT NULL
GROUP BY urgency
ORDER BY CASE urgency WHEN 'Emergency' THEN 1 WHEN 'High' THEN 2
                      WHEN 'Medium' THEN 3 ELSE 4 END;

-- 5. Within each fault type, which contractors are fastest, cheapest and best rated?
WITH job_stats AS (
    SELECT r.issue_category, k.contractor_name,
           COUNT(*) AS jobs,
           ROUND(AVG(DATEDIFF(DAY, r.date_noticed, r.date_resolved) * 1.0), 1) AS avg_days,
           ROUND(AVG(r.cost_nzd), 2) AS avg_cost,
           COUNT(r.satisfaction) AS ratings_given,
           ROUND(AVG(r.satisfaction * 1.0), 1) AS avg_satisfaction
    FROM requests r
    JOIN contractors k ON k.contractor_id = r.contractor_id
    WHERE r.date_resolved IS NOT NULL
    GROUP BY r.issue_category, k.contractor_name
)
SELECT issue_category, contractor_name, jobs, avg_days, avg_cost,
       ratings_given, avg_satisfaction,
       RANK() OVER (PARTITION BY issue_category ORDER BY avg_days) AS speed_rank
FROM job_stats
ORDER BY issue_category, speed_rank;

-- 6. Which faults keep coming back at the same property, and what has that cost?
-- Note: includes open requests, so "last_reported" may be an unresolved job.
SELECT p.address, r.description,
       COUNT(*) AS times_reported,
       MIN(r.date_noticed) AS first_reported,
       MAX(r.date_noticed) AS last_reported,
       SUM(r.cost_nzd) AS total_cost
FROM requests r
JOIN properties p ON p.property_id = r.property_id
GROUP BY p.address, r.description
HAVING COUNT(*) > 1
ORDER BY times_reported DESC, total_cost DESC;

-- 7 How long after a fix does the same fault come back? (LAG on resolution date)
-- Note: Negative values mean the fault was reported again before the previous job was resolved.
-- Includes open requests. A NULL previous_resolved would mean the earlier job is still open (none in this data).
WITH repeats AS (
    SELECT p.address, r.description, r.date_noticed,
           LAG(r.date_noticed) OVER (
               PARTITION BY r.property_id, r.description
               ORDER BY r.date_noticed, r.request_id) AS previous_report,
           LAG(r.date_resolved) OVER (
               PARTITION BY r.property_id, r.description
               ORDER BY r.date_noticed, r.request_id) AS previous_resolved
    FROM requests r
    JOIN properties p ON p.property_id = r.property_id
)
SELECT address, description, date_noticed, previous_report, previous_resolved,
       DATEDIFF(DAY, previous_resolved, date_noticed) AS days_after_fix
FROM repeats
WHERE previous_report IS NOT NULL
ORDER BY days_after_fix;

-- 8. Summary behind the repeat-fault finding in the README
WITH repeats AS (
    SELECT LAG(r.date_noticed) OVER (
               PARTITION BY r.property_id, r.description
               ORDER BY r.date_noticed, r.request_id) AS previous_report,
           DATEDIFF(DAY,
               LAG(r.date_resolved) OVER (
                   PARTITION BY r.property_id, r.description
                   ORDER BY r.date_noticed, r.request_id),
               r.date_noticed) AS days_after_fix
    FROM requests r
)
SELECT COUNT(*) AS repeat_reports,
       SUM(CASE WHEN days_after_fix < 0 THEN 1 ELSE 0 END) AS reported_before_fix,
       SUM(CASE WHEN days_after_fix BETWEEN 0 AND 14 THEN 1 ELSE 0 END) AS within_14_days,
       SUM(CASE WHEN days_after_fix BETWEEN 0 AND 30 THEN 1 ELSE 0 END) AS within_30_days
FROM repeats
WHERE previous_report IS NOT NULL;