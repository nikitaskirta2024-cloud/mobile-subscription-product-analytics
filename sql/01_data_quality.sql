-- ============================================================
-- 01. DATA QUALITY & CLEANING
-- Mobile Subscription Product Analytics
-- ============================================================


-- ============================================================
-- 1. PRIMARY KEY / DUPLICATE CHECKS
-- ============================================================

-- Check uniqueness of primary identifiers across core tables
SELECT
    'users' AS table_name,
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS unique_ids,
    COUNT(*) - COUNT(DISTINCT user_id) AS duplicate_rows
FROM `project-4-507020.1.users`

UNION ALL

SELECT
    'events',
    COUNT(*),
    COUNT(DISTINCT event_id),
    COUNT(*) - COUNT(DISTINCT event_id)
FROM `project-4-507020.1.events`

UNION ALL

SELECT
    'subscriptions',
    COUNT(*),
    COUNT(DISTINCT subscription_id),
    COUNT(*) - COUNT(DISTINCT subscription_id)
FROM `project-4-507020.1.subscriptions`

UNION ALL

SELECT
    'payments',
    COUNT(*),
    COUNT(DISTINCT payment_id),
    COUNT(*) - COUNT(DISTINCT payment_id)
FROM `project-4-507020.1.payments`

UNION ALL

SELECT
    'experiment_assignments',
    COUNT(*),
    COUNT(DISTINCT assignment_id),
    COUNT(*) - COUNT(DISTINCT assignment_id)
FROM `project-4-507020.1.experiment_assignments`;


-- Investigate duplicate event IDs:
-- distinguish exact duplicated rows from conflicting records
WITH duplicate_ids AS (
    SELECT
        event_id,
        COUNT(*) AS row_count,
        COUNT(DISTINCT TO_JSON_STRING(e)) AS distinct_rows
    FROM `project-4-507020.1.events` e
    GROUP BY event_id
    HAVING COUNT(*) > 1
)

SELECT
    COUNT(*) AS duplicated_event_ids,
    SUM(row_count - 1) AS extra_rows,
    COUNTIF(distinct_rows = 1) AS full_duplicates,
    COUNTIF(distinct_rows > 1) AS conflicting_duplicates
FROM duplicate_ids;


-- ============================================================
-- 2. IDENTIFIER COMPLETENESS
-- ============================================================

-- Events may be recorded before a user_id is attached.
-- Check whether anonymous_id can recover the canonical user.
SELECT
    COUNT(*) AS total_events,
    COUNTIF(e.user_id IS NULL) AS missing_user_id,
    COUNTIF(e.anonymous_id IS NULL) AS missing_anonymous_id,
    COUNTIF(
        e.user_id IS NULL
        AND e.anonymous_id IS NULL
    ) AS missing_both_ids,
    COUNTIF(
        e.user_id IS NULL
        AND u.user_id IS NOT NULL
    ) AS recoverable_via_anonymous_id
FROM `project-4-507020.1.events` e
LEFT JOIN `project-4-507020.1.users` u
    ON e.anonymous_id = u.anonymous_id;


-- ============================================================
-- 3. FOREIGN KEY / ORPHAN CHECKS
-- ============================================================

SELECT
    'events -> users' AS relationship,
    COUNT(*) AS orphan_rows
FROM `project-4-507020.1.events` e
LEFT JOIN `project-4-507020.1.users` u
    ON e.user_id = u.user_id
WHERE e.user_id IS NOT NULL
  AND u.user_id IS NULL

UNION ALL

SELECT
    'subscriptions -> users',
    COUNT(*)
FROM `project-4-507020.1.subscriptions` s
LEFT JOIN `project-4-507020.1.users` u
    ON s.user_id = u.user_id
WHERE u.user_id IS NULL

UNION ALL

SELECT
    'payments -> users',
    COUNT(*)
FROM `project-4-507020.1.payments` p
LEFT JOIN `project-4-507020.1.users` u
    ON p.user_id = u.user_id
WHERE u.user_id IS NULL

UNION ALL

SELECT
    'payments -> subscriptions',
    COUNT(*)
FROM `project-4-507020.1.payments` p
LEFT JOIN `project-4-507020.1.subscriptions` s
    ON p.subscription_id = s.subscription_id
WHERE s.subscription_id IS NULL

UNION ALL

SELECT
    'experiment_assignments -> users',
    COUNT(*)
FROM `project-4-507020.1.experiment_assignments` a
LEFT JOIN `project-4-507020.1.users` u
    ON a.user_id = u.user_id
WHERE u.user_id IS NULL;


-- ============================================================
-- 4. BUSINESS LOGIC / CHRONOLOGY CHECKS
-- ============================================================

-- Validate subscription lifecycle chronology
SELECT
    COUNTIF(
        trial_start_at IS NOT NULL
        AND trial_end_at IS NOT NULL
        AND trial_end_at < trial_start_at
    ) AS trial_end_before_start,

    COUNTIF(
        paid_start_at IS NOT NULL
        AND trial_start_at IS NOT NULL
        AND paid_start_at < trial_start_at
    ) AS paid_before_trial,

    COUNTIF(
        cancelled_at IS NOT NULL
        AND created_at IS NOT NULL
        AND cancelled_at < created_at
    ) AS cancellation_before_creation
FROM `project-4-507020.1.subscriptions`;


-- Check for payments occurring before subscription creation
SELECT
    COUNT(*) AS payments_before_subscription_creation
FROM `project-4-507020.1.payments` p
JOIN `project-4-507020.1.subscriptions` s
    ON p.subscription_id = s.subscription_id
WHERE p.transaction_ts < s.created_at;


-- ============================================================
-- 5. A/B ASSIGNMENT INTEGRITY
-- ============================================================

-- Detect users assigned to more than one variant
WITH user_assignments AS (
    SELECT
        experiment_id,
        user_id,
        COUNT(DISTINCT variant) AS variant_count
    FROM `project-4-507020.1.experiment_assignments`
    GROUP BY experiment_id, user_id
)

SELECT
    experiment_id,
    COUNT(*) AS assigned_users,
    COUNTIF(variant_count > 1) AS conflicting_users
FROM user_assignments
GROUP BY experiment_id;


-- ============================================================
-- 6. CLEAN ANALYTICAL VIEWS
-- ============================================================

-- Remove exact duplicate event rows
CREATE OR REPLACE VIEW `project-4-507020.1.events_clean` AS
SELECT DISTINCT *
FROM `project-4-507020.1.events`;


-- Remove exact duplicate payment rows
CREATE OR REPLACE VIEW `project-4-507020.1.payments_clean` AS
SELECT DISTINCT *
FROM `project-4-507020.1.payments`;


-- Recover canonical user_id from anonymous_id when possible
CREATE OR REPLACE VIEW `project-4-507020.1.events_user_level` AS
SELECT
    e.* EXCEPT(user_id),
    COALESCE(e.user_id, u.user_id) AS user_id
FROM `project-4-507020.1.events_clean` e
LEFT JOIN `project-4-507020.1.users` u
    ON e.anonymous_id = u.anonymous_id
WHERE COALESCE(e.user_id, u.user_id) IS NOT NULL;


-- Keep one valid experiment assignment per user and experiment.
-- Users assigned to conflicting variants are excluded.
CREATE OR REPLACE VIEW `project-4-507020.1.experiment_assignments_clean` AS
SELECT
    experiment_id,
    user_id,
    ANY_VALUE(variant) AS variant,
    MIN(assigned_at) AS assigned_at,
    MIN(eligible_at) AS eligible_at,
    ANY_VALUE(allocation_unit) AS allocation_unit,
    ANY_VALUE(assignment_source) AS assignment_source
FROM `project-4-507020.1.experiment_assignments`
GROUP BY experiment_id, user_id
HAVING COUNT(DISTINCT variant) = 1;
