-- ============================================================
-- 03. FUNNEL SEGMENTATION
-- Mobile Subscription Product Analytics
-- ============================================================

-- Compares funnel performance across:
-- region, acquisition channel, platform, device tier
-- and primary user goal.


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
        u.*,

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

segment_rows AS (
    SELECT
        uf.user_id,
        uf.onboarding_ts,
        uf.trial_ts,
        uf.paid_ts,
        s.dimension,
        s.segment
    FROM user_funnel uf

    CROSS JOIN UNNEST([
        STRUCT(
            'overall' AS dimension,
            'Overall' AS segment
        ),

        STRUCT(
            'region',
            COALESCE(uf.region, 'Unknown')
        ),

        STRUCT(
            'acquisition_channel',
            COALESCE(uf.acquisition_channel, 'Unknown')
        ),

        STRUCT(
            'platform',
            COALESCE(uf.platform, 'Unknown')
        ),

        STRUCT(
            'device_tier',
            COALESCE(uf.device_tier, 'Unknown')
        ),

        STRUCT(
            'primary_goal',
            COALESCE(uf.primary_goal, 'Unknown')
        )
    ]) s
),

aggregated AS (
    SELECT
        dimension,
        segment,

        COUNT(*) AS signup_users,
        COUNTIF(onboarding_ts IS NOT NULL) AS onboarding_users,
        COUNTIF(trial_ts IS NOT NULL) AS trial_users,
        COUNTIF(paid_ts IS NOT NULL) AS paid_users

    FROM segment_rows
    GROUP BY dimension, segment
)

SELECT
    dimension,
    segment,

    signup_users,
    onboarding_users,
    trial_users,
    paid_users,

    ROUND(
        100 * SAFE_DIVIDE(onboarding_users, signup_users),
        2
    ) AS signup_to_onboarding_pct,

    ROUND(
        100 * SAFE_DIVIDE(trial_users, onboarding_users),
        2
    ) AS onboarding_to_trial_pct,

    ROUND(
        100 * SAFE_DIVIDE(paid_users, trial_users),
        2
    ) AS trial_to_paid_pct,

    ROUND(
        100 * SAFE_DIVIDE(paid_users, signup_users),
        2
    ) AS signup_to_paid_pct

FROM aggregated
ORDER BY
    CASE dimension
        WHEN 'overall' THEN 1
        WHEN 'region' THEN 2
        WHEN 'acquisition_channel' THEN 3
        WHEN 'platform' THEN 4
        WHEN 'device_tier' THEN 5
        WHEN 'primary_goal' THEN 6
    END,
    segment;
