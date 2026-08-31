-- ============================================================
-- 06. A/B TEST ANALYTICAL DATASET
-- Mobile Subscription Product Analytics
-- Experiment: onboarding_flow_v2
-- ============================================================

-- Experimental groups are defined by experiment assignment (ITT).
-- Users with conflicting variant assignments were already excluded
-- in experiment_assignments_clean.
--
-- Primary metric:
--   onboarding completion
--
-- Secondary / guardrail metrics:
--   trial start
--   paid conversion
--   D1 / D7 / D30 retention


WITH experiment_users AS (
    SELECT
        user_id,
        variant,
        assigned_at
    FROM `project-4-507020.1.experiment_assignments_clean`
    WHERE experiment_id = 'onboarding_flow_v2'
),

data_window AS (
    SELECT
        MAX(DATE(event_ts)) AS data_end_date
    FROM `project-4-507020.1.events_user_level`
),

onboarding AS (
    SELECT
        e.user_id,
        MIN(e.event_ts) AS onboarding_ts
    FROM `project-4-507020.1.events_user_level` e
    JOIN experiment_users x
        ON e.user_id = x.user_id
    WHERE e.event_name = 'onboarding_completed'
      AND e.event_ts >= x.assigned_at
    GROUP BY e.user_id
),

trial AS (
    SELECT
        s.user_id,
        MIN(s.trial_start_at) AS trial_ts
    FROM `project-4-507020.1.subscriptions` s
    JOIN experiment_users x
        ON s.user_id = x.user_id
    WHERE s.trial_start_at IS NOT NULL
      AND s.trial_start_at >= x.assigned_at
    GROUP BY s.user_id
),

paid AS (
    SELECT
        p.user_id,
        MIN(p.transaction_ts) AS paid_ts
    FROM `project-4-507020.1.payments_clean` p
    JOIN experiment_users x
        ON p.user_id = x.user_id
    WHERE p.transaction_type = 'charge'
      AND p.status = 'captured'
      AND p.amount_usd > 0
      AND p.transaction_ts >= x.assigned_at
    GROUP BY p.user_id
),

app_open_days AS (
    SELECT DISTINCT
        user_id,
        DATE(event_ts) AS activity_date
    FROM `project-4-507020.1.events_user_level`
    WHERE event_name = 'app_open'
),

user_level AS (
    SELECT
        x.user_id,
        x.variant,
        x.assigned_at,
        u.signup_ts,
        dw.data_end_date,

        CASE
            WHEN o.onboarding_ts IS NOT NULL THEN 1
            ELSE 0
        END AS onboarding_completed,

        CASE
            WHEN t.trial_ts IS NOT NULL THEN 1
            ELSE 0
        END AS trial_started,

        CASE
            WHEN p.paid_ts IS NOT NULL THEN 1
            ELSE 0
        END AS paid_conversion,

        CASE
            WHEN DATE(u.signup_ts)
                 <= DATE_SUB(dw.data_end_date, INTERVAL 1 DAY)
            THEN 1 ELSE 0
        END AS d1_eligible,

        CASE
            WHEN DATE(u.signup_ts)
                 <= DATE_SUB(dw.data_end_date, INTERVAL 1 DAY)
             AND EXISTS (
                SELECT 1
                FROM app_open_days a
                WHERE a.user_id = x.user_id
                  AND a.activity_date =
                      DATE_ADD(DATE(u.signup_ts), INTERVAL 1 DAY)
             )
            THEN 1 ELSE 0
        END AS d1_retained,

        CASE
            WHEN DATE(u.signup_ts)
                 <= DATE_SUB(dw.data_end_date, INTERVAL 7 DAY)
            THEN 1 ELSE 0
        END AS d7_eligible,

        CASE
            WHEN DATE(u.signup_ts)
                 <= DATE_SUB(dw.data_end_date, INTERVAL 7 DAY)
             AND EXISTS (
                SELECT 1
                FROM app_open_days a
                WHERE a.user_id = x.user_id
                  AND a.activity_date =
                      DATE_ADD(DATE(u.signup_ts), INTERVAL 7 DAY)
             )
            THEN 1 ELSE 0
        END AS d7_retained,

        CASE
            WHEN DATE(u.signup_ts)
                 <= DATE_SUB(dw.data_end_date, INTERVAL 30 DAY)
            THEN 1 ELSE 0
        END AS d30_eligible,

        CASE
            WHEN DATE(u.signup_ts)
                 <= DATE_SUB(dw.data_end_date, INTERVAL 30 DAY)
             AND EXISTS (
                SELECT 1
                FROM app_open_days a
                WHERE a.user_id = x.user_id
                  AND a.activity_date =
                      DATE_ADD(DATE(u.signup_ts), INTERVAL 30 DAY)
             )
            THEN 1 ELSE 0
        END AS d30_retained

    FROM experiment_users x

    JOIN `project-4-507020.1.users` u
        ON x.user_id = u.user_id

    CROSS JOIN data_window dw

    LEFT JOIN onboarding o
        ON x.user_id = o.user_id

    LEFT JOIN trial t
        ON x.user_id = t.user_id

    LEFT JOIN paid p
        ON x.user_id = p.user_id
)

SELECT *
FROM user_level
ORDER BY variant, user_id;
