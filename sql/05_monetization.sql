-- ============================================================
-- 05. MONETIZATION ANALYSIS
-- Mobile Subscription Product Analytics
-- ============================================================

-- Metrics:
-- Trial -> Paid conversion
-- Paid-user cancellation rate
-- Gross revenue
-- Refunds
-- Net revenue
-- Refund share
-- Net revenue per payer
--
-- Revenue definition:
-- captured positive charges = gross revenue
-- captured negative refund rows = refunds
-- net revenue = sum of all captured payment amounts


WITH trial_users AS (
    SELECT DISTINCT
        user_id
    FROM `project-4-507020.1.subscriptions`
    WHERE trial_start_at IS NOT NULL
),

paid_users AS (
    SELECT DISTINCT
        user_id
    FROM `project-4-507020.1.payments_clean`
    WHERE transaction_type = 'charge'
      AND status = 'captured'
      AND amount_usd > 0
),

user_subscription AS (
    SELECT
        user_id,
        cancelled_at
    FROM `project-4-507020.1.subscriptions`
),

payment_metrics AS (
    SELECT
        user_id,

        SUM(
            CASE
                WHEN status = 'captured'
                 AND transaction_type = 'charge'
                 AND amount_usd > 0
                THEN amount_usd
                ELSE 0
            END
        ) AS gross_revenue_usd,

        ABS(
            SUM(
                CASE
                    WHEN status = 'captured'
                     AND amount_usd < 0
                    THEN amount_usd
                    ELSE 0
                END
            )
        ) AS refund_usd,

        SUM(
            CASE
                WHEN status = 'captured'
                THEN amount_usd
                ELSE 0
            END
        ) AS net_revenue_usd

    FROM `project-4-507020.1.payments_clean`
    GROUP BY user_id
),

user_level AS (
    SELECT
        u.user_id,
        u.region,
        u.acquisition_channel,
        u.platform,
        u.device_tier,
        u.primary_goal,

        CASE
            WHEN t.user_id IS NOT NULL THEN 1
            ELSE 0
        END AS is_trial_user,

        CASE
            WHEN p.user_id IS NOT NULL THEN 1
            ELSE 0
        END AS is_paid_user,

        CASE
            WHEN p.user_id IS NOT NULL
             AND s.cancelled_at IS NOT NULL
            THEN 1
            ELSE 0
        END AS is_cancelled_paid_user,

        COALESCE(pm.gross_revenue_usd, 0) AS gross_revenue_usd,
        COALESCE(pm.refund_usd, 0) AS refund_usd,
        COALESCE(pm.net_revenue_usd, 0) AS net_revenue_usd

    FROM `project-4-507020.1.users` u

    LEFT JOIN trial_users t
        ON u.user_id = t.user_id

    LEFT JOIN paid_users p
        ON u.user_id = p.user_id

    LEFT JOIN user_subscription s
        ON u.user_id = s.user_id

    LEFT JOIN payment_metrics pm
        ON u.user_id = pm.user_id
),

segment_rows AS (
    SELECT
        ul.*,
        s.dimension,
        s.segment

    FROM user_level ul

    CROSS JOIN UNNEST([
        STRUCT(
            'overall' AS dimension,
            'Overall' AS segment
        ),

        STRUCT(
            'region',
            COALESCE(ul.region, 'Unknown')
        ),

        STRUCT(
            'acquisition_channel',
            COALESCE(ul.acquisition_channel, 'Unknown')
        ),

        STRUCT(
            'platform',
            COALESCE(ul.platform, 'Unknown')
        ),

        STRUCT(
            'device_tier',
            COALESCE(ul.device_tier, 'Unknown')
        ),

        STRUCT(
            'primary_goal',
            COALESCE(ul.primary_goal, 'Unknown')
        )
    ]) s
),

aggregated AS (
    SELECT
        dimension,
        segment,

        COUNTIF(is_trial_user = 1) AS trial_users,
        COUNTIF(is_paid_user = 1) AS paid_users,
        COUNTIF(is_cancelled_paid_user = 1) AS cancelled_paid_users,

        SUM(gross_revenue_usd) AS gross_revenue_usd,
        SUM(refund_usd) AS refund_usd,
        SUM(net_revenue_usd) AS net_revenue_usd

    FROM segment_rows
    GROUP BY dimension, segment
)

SELECT
    dimension,
    segment,

    trial_users,
    paid_users,

    ROUND(
        100 * SAFE_DIVIDE(paid_users, trial_users),
        2
    ) AS trial_to_paid_pct,

    cancelled_paid_users,

    ROUND(
        100 * SAFE_DIVIDE(cancelled_paid_users, paid_users),
        2
    ) AS paid_cancellation_pct,

    ROUND(gross_revenue_usd, 2) AS gross_revenue_usd,
    ROUND(refund_usd, 2) AS refund_usd,
    ROUND(net_revenue_usd, 2) AS net_revenue_usd,

    ROUND(
        100 * SAFE_DIVIDE(refund_usd, gross_revenue_usd),
        2
    ) AS refund_share_pct,

    ROUND(
        SAFE_DIVIDE(net_revenue_usd, paid_users),
        2
    ) AS net_revenue_per_payer_usd

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
