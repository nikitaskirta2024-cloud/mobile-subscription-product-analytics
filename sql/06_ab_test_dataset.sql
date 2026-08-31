-- ============================================================
-- 06. A/B TEST ANALYTICAL DATASET
-- Mobile Subscription Product Analytics
-- Experiment: onboarding_flow_v2
-- ============================================================

-- Intention-to-treat (ITT) analysis.
-- Experiment groups are defined by assignment.
-- Conflicting variant assignments are excluded upstream.
--
-- Primary metric:
--   onboarding completion
--
-- Secondary / guardrail metrics:
--   trial start within 7 days of assignment
--   paid conversion within 14 days of assignment
--   exact-calendar D1 / D7 / D30 retention


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
        TIMESTAMP('2025-08-15 23:59:59+00') AS data_end_ts,
        DATE('2025-08-15') AS data_end_date
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
)

SELECT
    x.user_id,
    x.variant,
    x.assigned_at,
    u.signup_ts,
    dw.data_end_date,

    -- Primary metric
    IF(o.onboarding_ts IS NOT NULL, 1, 0)
        AS onboarding_completed,

    -- Trial: 7-day observation window
    IF(
        x.assigned_at <= TIMESTAMP_SUB(
            dw.data_end_ts,
            INTERVAL 7 DAY
        ),
        1,
        0
    ) AS trial_eligible,

    IF(
        t.trial_ts BETWEEN
            x.assigned_at
            AND TIMESTAMP_ADD(x.assigned_at, INTERVAL 7 DAY),
        1,
        0
    ) AS trial_started,

    -- Paid conversion: 14-day observation window
    IF(
        x.assigned_at <= TIMESTAMP_SUB(
            dw.data_end_ts,
            INTERVAL 14 DAY
        ),
        1,
        0
    ) AS paid_eligible,

    IF(
        p.paid_ts BETWEEN
            x.assigned_at
            AND TIMESTAMP_ADD(x.assigned_at, INTERVAL 14 DAY),
        1,
        0
    ) AS paid_conversion,

    -- D1 retention
    IF(
        DATE(u.signup_ts)
            <= DATE_SUB(dw.data_end_date, INTERVAL 1 DAY),
        1,
        0
    ) AS d1_eligible,

    IF(
        EXISTS (
            SELECT 1
            FROM app_open_days a
            WHERE a.user_id = x.user_id
              AND a.activity_date =
                  DATE_ADD(
                      DATE(u.signup_ts),
                      INTERVAL 1 DAY
                  )
        ),
        1,
        0
    ) AS d1_retained,

    -- D7 retention
    IF(
        DATE(u.signup_ts)
            <= DATE_SUB(dw.data_end_date, INTERVAL 7 DAY),
        1,
        0
    ) AS d7_eligible,

    IF(
        EXISTS (
            SELECT 1
            FROM app_open_days a
            WHERE a.user_id = x.user_id
              AND a.activity_date =
                  DATE_ADD(
                      DATE(u.signup_ts),
                      INTERVAL 7 DAY
                  )
        ),
        1,
        0
    ) AS d7_retained,

    -- D30 retention
    IF(
        DATE(u.signup_ts)
            <= DATE_SUB(dw.data_end_date, INTERVAL 30 DAY),
        1,
        0
    ) AS d30_eligible,

    IF(
        EXISTS (
            SELECT 1
            FROM app_open_days a
            WHERE a.user_id = x.user_id
              AND a.activity_date =
                  DATE_ADD(
                      DATE(u.signup_ts),
                      INTERVAL 30 DAY
                  )
        ),
        1,
        0
    ) AS d30_retained

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

ORDER BY
    x.variant,
    x.user_id;
