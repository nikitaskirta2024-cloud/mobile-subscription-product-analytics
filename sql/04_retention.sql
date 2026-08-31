-- ============================================================
-- 04. RETENTION ANALYSIS
-- Mobile Subscription Product Analytics
-- ============================================================

-- Exact calendar-day retention:
-- D1  = app_open exactly 1 day after signup
-- D7  = app_open exactly 7 days after signup
-- D30 = app_open exactly 30 days after signup
--
-- Users are included in the denominator only when the dataset
-- contains a complete observation window for the retention day.


WITH data_window AS (
    SELECT
        MAX(DATE(event_ts)) AS data_end_date
    FROM `project-4-507020.1.events_user_level`
),

app_open_days AS (
    SELECT DISTINCT
        user_id,
        DATE(event_ts) AS activity_date
    FROM `project-4-507020.1.events_user_level`
    WHERE event_name = 'app_open'
),

user_retention AS (
    SELECT
        u.user_id,
        DATE(u.signup_ts) AS signup_date,
        FORMAT_DATE('%Y-%m', DATE(u.signup_ts)) AS signup_month,
        dw.data_end_date,

        MAX(
            CASE
                WHEN a.activity_date =
                     DATE_ADD(DATE(u.signup_ts), INTERVAL 1 DAY)
                THEN 1 ELSE 0
            END
        ) AS retained_d1,

        MAX(
            CASE
                WHEN a.activity_date =
                     DATE_ADD(DATE(u.signup_ts), INTERVAL 7 DAY)
                THEN 1 ELSE 0
            END
        ) AS retained_d7,

        MAX(
            CASE
                WHEN a.activity_date =
                     DATE_ADD(DATE(u.signup_ts), INTERVAL 30 DAY)
                THEN 1 ELSE 0
            END
        ) AS retained_d30

    FROM `project-4-507020.1.users` u
    CROSS JOIN data_window dw

    LEFT JOIN app_open_days a
        ON u.user_id = a.user_id
       AND a.activity_date IN (
            DATE_ADD(DATE(u.signup_ts), INTERVAL 1 DAY),
            DATE_ADD(DATE(u.signup_ts), INTERVAL 7 DAY),
            DATE_ADD(DATE(u.signup_ts), INTERVAL 30 DAY)
       )

    GROUP BY
        u.user_id,
        signup_date,
        signup_month,
        data_end_date
),

segment_rows AS (
    SELECT
        r.*,
        s.dimension,
        s.segment

    FROM user_retention r

    CROSS JOIN UNNEST([
        STRUCT(
            'overall' AS dimension,
            'Overall' AS segment
        ),
        STRUCT(
            'signup_month',
            r.signup_month
        )
    ]) s
),

aggregated AS (
    SELECT
        dimension,
        segment,

        COUNTIF(
            signup_date <= DATE_SUB(data_end_date, INTERVAL 1 DAY)
        ) AS d1_eligible_users,

        COUNTIF(
            signup_date <= DATE_SUB(data_end_date, INTERVAL 1 DAY)
            AND retained_d1 = 1
        ) AS d1_retained_users,

        COUNTIF(
            signup_date <= DATE_SUB(data_end_date, INTERVAL 7 DAY)
        ) AS d7_eligible_users,

        COUNTIF(
            signup_date <= DATE_SUB(data_end_date, INTERVAL 7 DAY)
            AND retained_d7 = 1
        ) AS d7_retained_users,

        COUNTIF(
            signup_date <= DATE_SUB(data_end_date, INTERVAL 30 DAY)
        ) AS d30_eligible_users,

        COUNTIF(
            signup_date <= DATE_SUB(data_end_date, INTERVAL 30 DAY)
            AND retained_d30 = 1
        ) AS d30_retained_users

    FROM segment_rows
    GROUP BY dimension, segment
)

SELECT
    dimension,
    segment,

    d1_eligible_users,
    d1_retained_users,
    ROUND(
        100 * SAFE_DIVIDE(d1_retained_users, d1_eligible_users),
        2
    ) AS d1_retention_pct,

    d7_eligible_users,
    d7_retained_users,
    ROUND(
        100 * SAFE_DIVIDE(d7_retained_users, d7_eligible_users),
        2
    ) AS d7_retention_pct,

    d30_eligible_users,
    d30_retained_users,
    ROUND(
        100 * SAFE_DIVIDE(d30_retained_users, d30_eligible_users),
        2
    ) AS d30_retention_pct

FROM aggregated
ORDER BY
    CASE dimension
        WHEN 'overall' THEN 1
        WHEN 'signup_month' THEN 2
    END,
    segment;
