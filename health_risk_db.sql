CREATE DATABASE IF NOT EXISTS health_risk_db;
USE health_risk_db;

CREATE TABLE customers (
    customer_id INT PRIMARY KEY AUTO_INCREMENT,
    age INT,
    weight INT,
    height INT,
    bmi DECIMAL(4,1),
    married ENUM('yes','no'),
    profession VARCHAR(20)
);

CREATE TABLE lifestyle_factors (
    customer_id INT PRIMARY KEY,
    exercise ENUM('none','low','medium','high'),
    sleep DECIMAL(3,1),
    sugar_intake ENUM('low','medium','high'),
    smoking ENUM('yes','no'),
    alcohol ENUM('yes','no'),
    health_risk ENUM('low','high'),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE staging_health_data (
    row_id INT AUTO_INCREMENT PRIMARY KEY,
    age INT,
    weight INT,
    height INT,
    exercise VARCHAR(20),
    sleep DECIMAL(3,1),
    sugar_intake VARCHAR(20),
    smoking VARCHAR(10),
    alcohol VARCHAR(10),
    married VARCHAR(10),
    profession VARCHAR(20),
    bmi DECIMAL(4,1),
    health_risk VARCHAR(10)
);

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/health_risk_data.csv'
INTO TABLE staging_health_data
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(age, weight, height, exercise, sleep, sugar_intake, smoking, alcohol, married, profession, bmi, health_risk);

INSERT INTO customers (customer_id, age, weight, height, bmi, married, profession)
SELECT row_id, age, weight, height, bmi, married, profession
FROM staging_health_data;

INSERT INTO lifestyle_factors (customer_id, exercise, sleep, sugar_intake, smoking, alcohol, health_risk)
SELECT row_id, exercise, sleep, sugar_intake, smoking, alcohol, health_risk
FROM staging_health_data;

-- What's the overall high-risk percentage across the full customer base? 
-- (single number, like the 69.8% headline from your EDA)
SELECT ROUND((COUNT(*)/(SELECT COUNT(*) FROM lifestyle_factors) * 100.0),2) AS HIGH_RISK
FROM lifestyle_factors
WHERE health_risk = 'high';

-- For each profession, show the count of customers and the percentage classified as high risk. 
-- Only show professions where high-risk percentage exceeds 65%.
WITH health_risk_profession AS (
    SELECT 
        c.profession,
        COUNT(*) AS total_customers,
        COUNT(CASE WHEN l.health_risk = 'high' THEN 1 END) AS high_risk_count
    FROM customers c
    JOIN lifestyle_factors l ON c.customer_id = l.customer_id
    GROUP BY c.profession
)
SELECT 
    *,
    ROUND(high_risk_count / total_customers * 100.0, 2) AS high_risk_pct
FROM health_risk_profession
HAVING high_risk_pct > 65
ORDER BY high_risk_pct DESC;

-- Create age buckets (18–29, 30–39, 40–49, 50–59, 60+) using CASE WHEN, then show high-risk percentage per bucket.
WITH age_bucket AS (
	SELECT
		CASE
			WHEN c.age<=29 THEN '18-29'
			WHEN c.age<=39 THEN '30-39'
			WHEN c.age<=49 THEN '40-49'
			WHEN c.age<=59 THEN '50-59'
			ELSE '60+'
        END AS AGE_BIN,
        SUM(
			CASE WHEN l.health_risk = 'high' THEN 1 ELSE 0 END
        ) AS HIGH_HEALTH_RISK,
        COUNT(*) AS TOTAL_CUSTOMERS
        FROM customers c
        JOIN lifestyle_factors l
        ON c.customer_id = l.customer_id
        GROUP BY age_bin
) SELECT *, 
ROUND((HIGH_HEALTH_RISK/TOTAL_CUSTOMERS * 100.0),2) AS PERCENTAGE_HIGH_RISK 
FROM age_bucket
ORDER BY AGE_BIN ASC;

-- Join customers and lifestyle_factors, then find the average BMI and average sleep hours
-- for high-risk vs low-risk customers.
SELECT l.health_risk, ROUND(AVG(c.bmi),2) as AVG_BMI, ROUND(AVG(l.sleep),2) AS AVG_SLEEP_HOURS
FROM CUSTOMERS c
JOIN LIFESTYLE_FACTORS l
ON c.customer_id = l.customer_id
GROUP BY l.health_risk;

-- Risk burden score
WITH burden_rules AS (
	SELECT c.customer_id,
		CASE WHEN l.exercise = 'low' OR l.exercise = 'none' THEN 1 ELSE 0 END +
        CASE WHEN l.sleep < 6 THEN 1 ELSE 0 END +
        CASE WHEN l.sugar_intake = 'high' THEN 1 ELSE 0 END +
        CASE WHEN l.smoking = 'yes' THEN 1 ELSE 0 END +
        CASE WHEN l.alcohol = 'yes' THEN 1 ELSE 0 END +
        CASE WHEN c.bmi >= 30 THEN 1 ELSE 0 END
     AS burden_score,
     l.health_risk AS health_risk
    FROM CUSTOMERS c
    JOIN LIFESTYLE_FACTORS l
    ON c.customer_id = l.customer_id
) SELECT burden_score, 
COUNT(CASE WHEN health_risk = 'high' THEN 1 END) AS high_risk_customers,
COUNT(*) AS total_in_group, 
ROUND(COUNT(CASE WHEN health_risk = 'high' THEN 1 END)/COUNT(*) * 100.0,2) AS BURDEN_WISE_HIGH_RISK
 FROM burden_rules
 GROUP BY burden_score
 ORDER BY burden_score;
 
 -- 
 WITH smoker_low_exercise AS (
    SELECT 
        c.customer_id,
        l.health_risk
    FROM customers c
    JOIN lifestyle_factors l ON c.customer_id = l.customer_id
    WHERE l.smoking = 'yes' 
      AND (l.exercise = 'low' OR l.exercise = 'none')
),
overall_population AS (
    SELECT 
        health_risk
    FROM lifestyle_factors
)
SELECT 
    'Smokers + Low/No Exercise' AS segment,
    COUNT(*) AS total_customers,
    COUNT(CASE WHEN health_risk = 'high' THEN 1 END) AS high_risk_count,
    ROUND(COUNT(CASE WHEN health_risk = 'high' THEN 1 END) / COUNT(*) * 100.0, 2) AS high_risk_pct
FROM smoker_low_exercise

UNION ALL

SELECT 
    'Overall Population' AS segment,
    COUNT(*) AS total_customers,
    COUNT(CASE WHEN health_risk = 'high' THEN 1 END) AS high_risk_count,
    ROUND(COUNT(CASE WHEN health_risk = 'high' THEN 1 END) / COUNT(*) * 100.0, 2) AS high_risk_pct
FROM overall_population;

-- ════════════════════════════════════════════
-- Query 7: Profession Ranking (RANK / DENSE_RANK)
-- ════════════════════════════════════════════

WITH profession_risk AS (
    SELECT 
        c.profession,
        COUNT(*) AS total_customers,
        COUNT(CASE WHEN l.health_risk = 'high' THEN 1 END) AS high_risk_count,
        ROUND(COUNT(CASE WHEN l.health_risk = 'high' THEN 1 END) / COUNT(*) * 100.0, 2) AS high_risk_pct
    FROM customers c
    JOIN lifestyle_factors l ON c.customer_id = l.customer_id
    GROUP BY c.profession
)
SELECT 
    profession,
    total_customers,
    high_risk_pct,
    RANK() OVER (ORDER BY high_risk_pct DESC) AS risk_rank
FROM profession_risk
ORDER BY risk_rank;


-- ════════════════════════════════════════════
-- Query 8: Cumulative Average Across Age Buckets
-- ════════════════════════════════════════════

WITH age_bucket AS (
    SELECT
        c.customer_id,
        CASE
            WHEN c.age <= 29 THEN '18-29'
            WHEN c.age <= 39 THEN '30-39'
            WHEN c.age <= 49 THEN '40-49'
            WHEN c.age <= 59 THEN '50-59'
            ELSE '60+'
        END AS age_bin,
        CASE
            WHEN c.age <= 29 THEN 1
            WHEN c.age <= 39 THEN 2
            WHEN c.age <= 49 THEN 3
            WHEN c.age <= 59 THEN 4
            ELSE 5
        END AS age_order,
        l.health_risk
    FROM customers c
    JOIN lifestyle_factors l ON c.customer_id = l.customer_id
),
age_risk AS (
    SELECT 
        age_bin,
        age_order,
        COUNT(*) AS total_customers,
        ROUND(COUNT(CASE WHEN health_risk = 'high' THEN 1 END) / COUNT(*) * 100.0, 2) AS high_risk_pct
    FROM age_bucket
    GROUP BY age_bin, age_order
)
SELECT 
    age_bin,
    total_customers,
    high_risk_pct,
    ROUND(AVG(high_risk_pct) OVER (ORDER BY age_order ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS cumulative_avg_risk_pct
FROM age_risk
ORDER BY age_order;


-- ════════════════════════════════════════════
-- Query 9: Profession × Age Group Heatmap (Two CTEs)
-- ════════════════════════════════════════════

WITH age_bucket AS (
    SELECT
        c.customer_id,
        c.profession,
        CASE
            WHEN c.age <= 29 THEN '18-29'
            WHEN c.age <= 39 THEN '30-39'
            WHEN c.age <= 49 THEN '40-49'
            WHEN c.age <= 59 THEN '50-59'
            ELSE '60+'
        END AS age_bin,
        l.health_risk
    FROM customers c
    JOIN lifestyle_factors l ON c.customer_id = l.customer_id
),
profession_age_risk AS (
    SELECT 
        profession,
        age_bin,
        COUNT(*) AS total_customers,
        ROUND(COUNT(CASE WHEN health_risk = 'high' THEN 1 END) / COUNT(*) * 100.0, 2) AS high_risk_pct
    FROM age_bucket
    GROUP BY profession, age_bin
)
SELECT *
FROM profession_age_risk
ORDER BY profession, 
    FIELD(age_bin, '18-29', '30-39', '40-49', '50-59', '60+');


-- ════════════════════════════════════════════
-- Query 10: Highest-Risk Profession per Age Group
-- ════════════════════════════════════════════

WITH age_bucket AS (
    SELECT
        c.customer_id,
        c.profession,
        CASE
            WHEN c.age <= 29 THEN '18-29'
            WHEN c.age <= 39 THEN '30-39'
            WHEN c.age <= 49 THEN '40-49'
            WHEN c.age <= 59 THEN '50-59'
            ELSE '60+'
        END AS age_bin,
        l.health_risk
    FROM customers c
    JOIN lifestyle_factors l ON c.customer_id = l.customer_id
),
profession_age_risk AS (
    SELECT 
        profession,
        age_bin,
        COUNT(*) AS total_customers,
        ROUND(COUNT(CASE WHEN health_risk = 'high' THEN 1 END) / COUNT(*) * 100.0, 2) AS high_risk_pct
    FROM age_bucket
    GROUP BY profession, age_bin
),
ranked AS (
    SELECT 
        *,
        RANK() OVER (PARTITION BY age_bin ORDER BY high_risk_pct DESC) AS risk_rank
    FROM profession_age_risk
)
SELECT 
    age_bin,
    profession AS highest_risk_profession,
    high_risk_pct
FROM ranked
WHERE risk_rank = 1
ORDER BY FIELD(age_bin, '18-29', '30-39', '40-49', '50-59', '60+');