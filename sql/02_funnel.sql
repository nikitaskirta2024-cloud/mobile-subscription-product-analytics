-- ============================================================
-- 02. PRODUCT FUNNEL
-- Mobile Subscription Product Analytics
-- ============================================================

-- Funnel definition:
-- Signup -> Onboarding Completed -> Trial Started -> Paid
--
-- Each step is counted only if it happened after the previous
-- step for the same user.


WITH onboarding AS (
    SELECT
        user_id,
        MIN(event_ts) AS onboarding_ts
    FROM `project-4-507020.1.events_user_level`
    WHERE event_name = 'onboarding_completed'
    GROUP BY user_id
),

trial AS (
    SELECT
        user_id,
        MIN(trial_start_at) AS trial_ts
    FROM `project-4-507020.1.subscriptions`
    WHERE trial_start_at IS NOT NULL
    GROUP BY user_id
),

paid AS (
    SELECT
        user_id,
        MIN(transaction_ts) AS paid_ts
    FROM `project-4-507020.1.payments_clean`
    WHERE transaction_type = 'charge'
      AND status = 'captured'
      AND amount_usd > 0
    GROUP BY user_id
),

user_funnel AS (
    SELECT
        u.user_id,
        u.signup_ts,

        CASE
            WHEN o.onboarding_ts >= u.signup_ts
            THEN o.onboarding_ts
        END AS onboarding_ts,

        CASE
            WHEN o.onboarding_ts >= u.signup_ts
             AND t.trial_ts >= o.onboarding_ts
            THEN t.trial_ts
        END AS trial_ts,

        CASE
            WHEN o.onboarding_ts >= u.signup_ts
             AND t.trial_ts >= o.onboarding_ts
             AND p.paid_ts >= t.trial_ts
            THEN p.paid_ts
        END AS paid_ts

    FROM `project-4-507020.1.users` u

    LEFT JOIN onboarding o
        ON u.user_id = o.user_id

    LEFT JOIN trial t
        ON u.user_id = t.user_id

    LEFT JOIN paid p
        ON u.user_id = p.user_id
),

funnel_counts AS (
    SELECT
        COUNT(*) AS signup_users,
        COUNTIF(onboarding_ts IS NOT NULL) AS onboarding_users,
        COUNTIF(trial_ts IS NOT NULL) AS trial_users,
        COUNTIF(paid_ts IS NOT NULL) AS paid_users
    FROM user_funnel
),

funnel AS (
    SELECT
        1 AS step_order,
        'signup' AS step,
        signup_users AS users,
        100.00 AS conversion_from_previous_pct
    FROM funnel_counts

    UNION ALL

    SELECT
        2,
        'onboarding_completed',
        onboarding_users,
        ROUND(
            100 * SAFE_DIVIDE(onboarding_users, signup_users),
            2
        )
    FROM funnel_counts

    UNION ALL

    SELECT
        3,
        'trial_started',
        trial_users,
        ROUND(
            100 * SAFE_DIVIDE(trial_users, onboarding_users),
            2
        )
    FROM funnel_counts

    UNION ALL

    SELECT
        4,
        'paid',
        paid_users,
        ROUND(
            100 * SAFE_DIVIDE(paid_users, trial_users),
            2
        )
    FROM funnel_counts
)

SELECT
    step,
    users,
    conversion_from_previous_pct
FROM funnel
ORDER BY step_order;
