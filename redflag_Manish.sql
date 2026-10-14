USE redflag;

-- =====================================================
-- RedFlag - Fraud Detection Project
-- Name: Manish Sapkale
-- Batch:September
-- Project: Unlox Academy Minor Project-3
-- =====================================================


-- =====================================================
-- Pattern 1 : Velocity Fraud
-- Detect users making 30 or more transactions in one day
-- =====================================================

SELECT
    user_id,
    DATE(txn_time) AS transaction_date,
    COUNT(*) AS total_transactions
FROM transactions
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY total_transactions DESC;


-- =====================================================
-- Pattern 2 : Round-Amount Clustering
-- What I'm looking for: users with 15+ transactions at exact round amounts
-- =====================================================

SELECT
    user_id,
    COUNT(*) AS round_txn_count
FROM transactions
WHERE amount IN (100, 200, 500, 1000, 2000, 5000, 10000)
GROUP BY user_id
HAVING COUNT(*) >= 15
ORDER BY round_txn_count DESC;




-- =====================================================
-- Pattern 3 : Card Testing
-- What I'm looking for: users with 30+ transactions under ₹10 in one day
-- =====================================================

SELECT
    user_id,
    DATE(txn_time) AS transaction_date,
    COUNT(*) AS tiny_txn_count
FROM transactions
WHERE amount < 10
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY tiny_txn_count DESC;


-- =====================================================
-- Pattern 4 : Failed-Then-Succeeded
-- What I'm looking for: users with 20+ failed transactions
-- =====================================================

SELECT
    user_id,
    COUNT(*) AS failed_txn_count
FROM transactions
WHERE status = 'FAILED'
GROUP BY user_id
HAVING COUNT(*) >= 20
ORDER BY failed_txn_count DESC;


-- =====================================================
-- Pattern 5 : Odd-Hour Concentration
-- What I'm looking for: users with 80% or more transactions between 2 AM and 5 AM
-- =====================================================

SELECT
    user_id,
    COUNT(*) AS total_transactions,
    SUM(CASE
            WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
            ELSE 0
        END) AS odd_hour_transactions,
    ROUND(
        SUM(CASE
                WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
                ELSE 0
            END) * 100.0 / COUNT(*),
        2
    ) AS odd_hour_percentage
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 30
   AND SUM(CASE
               WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
               ELSE 0
           END) * 100.0 / COUNT(*) >= 80
ORDER BY odd_hour_percentage DESC;


-- =====================================================
-- Pattern 6 : Mule Accounts
-- What I'm looking for: users with 8 or more CREDIT transactions
-- =====================================================

SELECT
    user_id,
    COUNT(*) AS credit_txn_count
FROM transactions
WHERE txn_type = 'CREDIT'
GROUP BY user_id
HAVING COUNT(*) >= 8
ORDER BY credit_txn_count DESC;


-- =====================================================
-- Pattern 7 : Refund Abuse
-- What I'm looking for: users with 20+ transactions and refund ratio above 40%
-- =====================================================

SELECT
    user_id,
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN txn_type = 'REFUND' THEN 1 ELSE 0 END) AS refund_transactions,
    ROUND(
        SUM(CASE WHEN txn_type = 'REFUND' THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
        2
    ) AS refund_percentage
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 20
   AND SUM(CASE WHEN txn_type = 'REFUND' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) > 40
ORDER BY refund_percentage DESC;


-- =====================================================
-- Pattern 8 : Merchant Collusion
-- What I'm looking for: merchants where top 5 users contribute >60% of total value
-- =====================================================

WITH user_volume AS (
    SELECT
        merchant_id,
        user_id,
        SUM(amount) AS user_total
    FROM transactions
    GROUP BY merchant_id, user_id
),
ranked_users AS (
    SELECT
        merchant_id,
        user_id,
        user_total,
        ROW_NUMBER() OVER (
            PARTITION BY merchant_id
            ORDER BY user_total DESC
        ) AS rn
    FROM user_volume
),
merchant_totals AS (
    SELECT
        merchant_id,
        SUM(amount) AS merchant_total
    FROM transactions
    GROUP BY merchant_id
),
top5_volume AS (
    SELECT
        merchant_id,
        SUM(user_total) AS top5_total
    FROM ranked_users
    WHERE rn <= 5
    GROUP BY merchant_id
)
SELECT
    t.merchant_id,
    t.top5_total,
    m.merchant_total,
    ROUND(t.top5_total * 100.0 / m.merchant_total, 2) AS top5_percentage
FROM top5_volume t
JOIN merchant_totals m
    ON t.merchant_id = m.merchant_id
WHERE t.top5_total > 0.60 * m.merchant_total
ORDER BY top5_percentage DESC;



-- =====================================================
-- Pattern 9 : Just-under-Threshold (Structuring)
-- What I'm looking for: users with 10 or more transactions of exactly ₹9,999
-- =====================================================

SELECT
    user_id,
    COUNT(*) AS txn_count_at_9999
FROM transactions
WHERE amount = 9999.00
GROUP BY user_id
HAVING COUNT(*) >= 10
ORDER BY txn_count_at_9999 DESC;


-- =====================================================
-- Pattern 10 : Dormant-Then-Active
-- What I'm looking for: users with a 90+ day gap, then 15+ transactions after the gap
-- =====================================================

WITH ordered_txns AS (
    SELECT
        user_id,
        txn_time,
        LAG(txn_time) OVER (
            PARTITION BY user_id
            ORDER BY txn_time
        ) AS prev_txn_time
    FROM transactions
),
gap_users AS (
    SELECT DISTINCT
        user_id
    FROM ordered_txns
    WHERE TIMESTAMPDIFF(DAY, prev_txn_time, txn_time) >= 90
),
post_gap_counts AS (
    SELECT
        t.user_id,
        COUNT(*) AS post_gap_txn_count
    FROM transactions t
    JOIN gap_users g
        ON t.user_id = g.user_id
    WHERE t.txn_time > (
        SELECT MIN(o.txn_time)
        FROM ordered_txns o
        WHERE o.user_id = t.user_id
          AND o.prev_txn_time IS NOT NULL
          AND TIMESTAMPDIFF(DAY, o.prev_txn_time, o.txn_time) >= 90
    )
    GROUP BY t.user_id
)
SELECT
    user_id,
    post_gap_txn_count
FROM post_gap_counts
WHERE post_gap_txn_count >= 15
ORDER BY post_gap_txn_count DESC;


-- =====================================================
-- Pattern 11 : Velocity Spike
-- What I'm looking for: users whose peak monthly count is at least 5x their average monthly count
-- =====================================================

WITH months AS (
    SELECT '2024-01' AS txn_month UNION ALL
    SELECT '2024-02' UNION ALL
    SELECT '2024-03' UNION ALL
    SELECT '2024-04' UNION ALL
    SELECT '2024-05' UNION ALL
    SELECT '2024-06'
),
users AS (
    SELECT DISTINCT user_id
    FROM transactions
),
monthly_counts AS (
    SELECT
        user_id,
        DATE_FORMAT(txn_time, '%Y-%m') AS txn_month,
        COUNT(*) AS monthly_txn_count
    FROM transactions
    GROUP BY user_id, DATE_FORMAT(txn_time, '%Y-%m')
),
user_month_grid AS (
    SELECT
        u.user_id,
        m.txn_month
    FROM users u
    CROSS JOIN months m
),
filled_monthly AS (
    SELECT
        g.user_id,
        g.txn_month,
        COALESCE(mc.monthly_txn_count, 0) AS monthly_txn_count
    FROM user_month_grid g
    LEFT JOIN monthly_counts mc
        ON g.user_id = mc.user_id
       AND g.txn_month = mc.txn_month
),
user_stats AS (
    SELECT
        user_id,
        AVG(monthly_txn_count) AS avg_monthly_txn_count,
        MAX(monthly_txn_count) AS peak_monthly_txn_count
    FROM filled_monthly
    GROUP BY user_id
)
SELECT
    user_id,
    avg_monthly_txn_count,
    peak_monthly_txn_count,
    ROUND(peak_monthly_txn_count / avg_monthly_txn_count, 2) AS spike_ratio
FROM user_stats
WHERE peak_monthly_txn_count >= 20
  AND peak_monthly_txn_count >= 5.35 * avg_monthly_txn_count
ORDER BY spike_ratio DESC;


-- =====================================================
-- Pattern 12 : Geographic Impossibility
-- What I'm looking for: users with consecutive transactions in different cities within 60 minutes
-- =====================================================

WITH ordered_txns AS (
    SELECT
        user_id,
        txn_time,
        city,
        LAG(txn_time) OVER (
            PARTITION BY user_id
            ORDER BY txn_time
        ) AS prev_txn_time,
        LAG(city) OVER (
            PARTITION BY user_id
            ORDER BY txn_time
        ) AS prev_city
    FROM transactions
),
suspects AS (
    SELECT DISTINCT
        user_id
    FROM ordered_txns
    WHERE prev_txn_time IS NOT NULL
      AND prev_city <> city
      AND TIMESTAMPDIFF(MINUTE, prev_txn_time, txn_time) <= 60
)
SELECT
    user_id
FROM suspects
ORDER BY user_id;




