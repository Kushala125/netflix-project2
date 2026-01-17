--Verify data exists
SELECT COUNT(*) FROM postings;
PRAGMA table_info(postings);
--Exclude invalid records
SELECT *
FROM postings
WHERE company IS NOT NULL
  AND job_title IS NOT NULL;
  --Feature Engineering in SQL
  SELECT
    CASE
        WHEN lower("job level") LIKE '%junior%'
          OR lower("job level") LIKE '%entry%' THEN 'Junior'
        WHEN lower("job level") LIKE '%senior%'
          OR lower("job level") LIKE '%lead%'
          OR lower("job level") LIKE '%staff%' THEN 'Senior'
        ELSE 'Mid'
    END AS job_level_clean,
    COUNT(*) AS jobs
FROM postings
GROUP BY job_level_clean;
--Time Feature (Year–Month)
SELECT
    substr(first_seen, 1, 7) AS year_month,
    COUNT(*) AS jobs
FROM postings
GROUP BY year_month
ORDER BY year_month;
--Work Mode Feature (Remote vs Onsite)
SELECT
    CASE
        WHEN lower(job_type) LIKE '%remote%' THEN 'Remote'
        ELSE 'Onsite/Hybrid'
    END AS work_mode,
    COUNT(*) AS jobs
FROM postings
GROUP BY work_mode;
--Exploratory Data Analysis
--Hiring Trend Over Time
SELECT
    substr(first_seen, 1, 7) AS year_month,
    COUNT(*) AS jobs_posted
FROM postings
GROUP BY year_month
ORDER BY year_month;
--Remote Hiring Trend Over Time
SELECT
    substr(first_seen, 1, 7) AS year_month,
    SUM(CASE WHEN lower(job_type) LIKE '%remote%' THEN 1 ELSE 0 END) AS remote_jobs,
    COUNT(*) AS total_jobs
FROM postings
GROUP BY year_month
ORDER BY year_month;
--Job Level Distribution
SELECT
    CASE
        WHEN lower("job level") LIKE '%junior%'
          OR lower("job level") LIKE '%entry%' THEN 'Junior'
        WHEN lower("job level") LIKE '%senior%'
          OR lower("job level") LIKE '%lead%'
          OR lower("job level") LIKE '%staff%' THEN 'Senior'
        ELSE 'Mid'
    END AS job_level,
    COUNT(*) AS jobs
FROM postings
GROUP BY job_level
ORDER BY jobs DESC;
--Top Hiring Companies
SELECT
    company,
    COUNT(*) AS total_jobs
FROM postings
GROUP BY company
ORDER BY total_jobs DESC
LIMIT 10;
--Hiring Consistency vs Volatility (Advanced)
WITH monthly_hiring AS (
    SELECT
        company,
        substr(first_seen, 1, 7) AS year_month,
        COUNT(*) AS jobs_per_month
    FROM postings
    GROUP BY company, year_month
),
stats AS (
    SELECT
        company,
        AVG(jobs_per_month) AS avg_jobs,
        AVG(jobs_per_month * jobs_per_month) AS avg_jobs_sq
    FROM monthly_hiring
    GROUP BY company
)
SELECT
    company,
    ROUND(avg_jobs, 2) AS avg_monthly_hiring,
    ROUND(
        sqrt(avg_jobs_sq - avg_jobs * avg_jobs),
        2
    ) AS hiring_volatility
FROM stats
ORDER BY hiring_volatility ASC;
--Remote Hiring Share by Company
SELECT
    company,
    ROUND(
        100.0 * SUM(CASE WHEN lower(job_type) LIKE '%remote%' THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS remote_share_percent
FROM postings
GROUP BY company
HAVING COUNT(*) >= 20
ORDER BY remote_share_percent DESC;
--Hiring Focus by Job Level
SELECT
    company,
    CASE
        WHEN lower("job level") LIKE '%junior%'
          OR lower("job level") LIKE '%entry%' THEN 'Junior'
        WHEN lower("job level") LIKE '%senior%'
          OR lower("job level") LIKE '%lead%'
          OR lower("job level") LIKE '%staff%' THEN 'Senior'
        ELSE 'Mid'
    END AS job_level,
    COUNT(*) AS job_count,
    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (PARTITION BY company),
        1
    ) AS level_share_percent
FROM postings
GROUP BY company, job_level
ORDER BY company, level_share_percent DESC;
--Monthly Hiring View
CREATE VIEW monthly_hiring_trend AS
SELECT
    substr(first_seen, 1, 7) AS year_month,
    COUNT(*) AS jobs_posted
FROM postings
GROUP BY year_month;
--Company Hiring Summary View
CREATE VIEW company_hiring_summary AS
SELECT
    company,
    COUNT(*) AS total_jobs
FROM postings
GROUP BY company;
-- Which companies are accelerating hiring, not just hiring a lot?
WITH monthly_jobs AS (
    SELECT
        company,
        substr(first_seen, 1, 7) AS year_month,
        COUNT(*) AS jobs
    FROM postings
    GROUP BY company, year_month
),
company_trends AS (
    SELECT
        company,
        SUM(CASE 
              WHEN year_month >= strftime('%Y-%m', date('now', '-3 month'))
              THEN jobs ELSE 0 END) AS recent_jobs,
        SUM(CASE 
              WHEN year_month < strftime('%Y-%m', date('now', '-3 month'))
              THEN jobs ELSE 0 END) AS past_jobs
    FROM monthly_jobs
    GROUP BY company
)
SELECT
    company,
    recent_jobs,
    past_jobs,
    ROUND(1.0 * recent_jobs / NULLIF(past_jobs, 0), 2) AS hiring_momentum_index
FROM company_trends
ORDER BY hiring_momentum_index DESC;
--Which companies hire steadily vs in unpredictable bursts?
WITH monthly_jobs AS (
    SELECT
        company,
        substr(first_seen, 1, 7) AS year_month,
        COUNT(*) AS jobs
    FROM postings
    GROUP BY company, year_month
),
stats AS (
    SELECT
        company,
        AVG(jobs) AS avg_jobs,
        AVG(jobs * jobs) AS avg_jobs_sq
    FROM monthly_jobs
    GROUP BY company
)
SELECT
    company,
    ROUND(avg_jobs, 2) AS avg_monthly_jobs,
    ROUND(
        sqrt(avg_jobs_sq - avg_jobs * avg_jobs),
        2
    ) AS hiring_volatility,
    ROUND(
        avg_jobs / NULLIF(sqrt(avg_jobs_sq - avg_jobs * avg_jobs), 0),
        2
    ) AS stability_score
FROM stats
ORDER BY stability_score DESC;
--JOB LEVEL CONCENTRATION INDEX (WINDOW FUNCTION)
--Do companies focus on one job level or diversify hiring?
WITH level_counts AS (
    SELECT
        company,
        CASE
            WHEN lower("job level") LIKE '%junior%'
              OR lower("job level") LIKE '%entry%' THEN 'Junior'
            WHEN lower("job level") LIKE '%senior%'
              OR lower("job level") LIKE '%lead%'
              OR lower("job level") LIKE '%staff%' THEN 'Senior'
            ELSE 'Mid'
        END AS job_level,
        COUNT(*) AS jobs
    FROM postings
    GROUP BY company, job_level
)
SELECT
    company,
    job_level,
    jobs,
    ROUND(
        100.0 * jobs / SUM(jobs) OVER (PARTITION BY company),
        1
    ) AS level_share_percent
FROM level_counts
ORDER BY company, level_share_percent DESC;
--Which companies are shifting toward remote work?
WITH monthly_remote AS (
    SELECT
        company,
        substr(first_seen, 1, 7) AS year_month,
        SUM(CASE WHEN lower(job_type) LIKE '%remote%' THEN 1 ELSE 0 END) AS remote_jobs,
        COUNT(*) AS total_jobs
    FROM postings
    GROUP BY company, year_month
)
SELECT
    company,
    year_month,
    ROUND(100.0 * remote_jobs / total_jobs, 1) AS remote_share
FROM monthly_remote
WHERE total_jobs >= 5
ORDER BY company, year_month;
--Is the market skewed toward junior or senior roles over time?
WITH job_levels AS (
    SELECT
        substr(first_seen, 1, 7) AS year_month,
        CASE
            WHEN lower("job level") LIKE '%junior%'
              OR lower("job level") LIKE '%entry%' THEN 'Junior'
            WHEN lower("job level") LIKE '%senior%'
              OR lower("job level") LIKE '%lead%'
              OR lower("job level") LIKE '%staff%' THEN 'Senior'
            ELSE 'Mid'
        END AS job_level
    FROM postings
)
SELECT
    year_month,
    SUM(CASE WHEN job_level = 'Senior' THEN 1 ELSE 0 END) AS senior_jobs,
    SUM(CASE WHEN job_level = 'Junior' THEN 1 ELSE 0 END) AS junior_jobs,
    CASE
        WHEN SUM(CASE WHEN job_level = 'Junior' THEN 1 ELSE 0 END) = 0
        THEN 'No Junior Roles'
        ELSE ROUND(
            1.0 * SUM(CASE WHEN job_level = 'Senior' THEN 1 ELSE 0 END)
            /
            SUM(CASE WHEN job_level = 'Junior' THEN 1 ELSE 0 END),
            2
        )
    END AS senior_to_junior_ratio
FROM job_levels
GROUP BY year_month
ORDER BY year_month;
--Which companies dominate the hiring market each month?
WITH monthly_totals AS (
    SELECT
        substr(first_seen, 1, 7) AS year_month,
        COUNT(*) AS total_jobs
    FROM postings
    GROUP BY year_month
),
company_monthly AS (
    SELECT
        company,
        substr(first_seen, 1, 7) AS year_month,
        COUNT(*) AS company_jobs
    FROM postings
    GROUP BY company, year_month
)
SELECT
    c.company,
    c.year_month,
    ROUND(
        100.0 * c.company_jobs / t.total_jobs,
        2
    ) AS market_share_percent
FROM company_monthly c
JOIN monthly_totals t
  ON c.year_month = t.year_month
ORDER BY market_share_percent DESC;
--STABILITY SCORE
WITH monthly_hiring AS (
    SELECT
        company,
        substr(first_seen, 1, 7) AS year_month,
        COUNT(*) AS jobs_per_month
    FROM postings
    GROUP BY company, year_month
),
stats AS (
    SELECT
        company,
        AVG(jobs_per_month) AS avg_jobs,
        AVG(jobs_per_month * jobs_per_month) AS avg_jobs_sq
    FROM monthly_hiring
    GROUP BY company
)
SELECT
    company,
    ROUND(avg_jobs, 2) AS avg_monthly_hiring,
    ROUND(
        sqrt(avg_jobs_sq - avg_jobs * avg_jobs),
        2
    ) AS hiring_volatility,
    ROUND(
        avg_jobs / NULLIF(sqrt(avg_jobs_sq - avg_jobs * avg_jobs), 0),
        2
    ) AS stability_score
FROM stats
ORDER BY stability_score DESC;






