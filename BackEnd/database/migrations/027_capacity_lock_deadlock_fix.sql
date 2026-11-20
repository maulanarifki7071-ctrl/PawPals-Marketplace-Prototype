
SELECT
  position(
    'FOR NO KEY UPDATE' IN
    pg_get_functiondef(
      'public.pawpals_capacity_deferred_guard()'::regprocedure
    )
  ) > 0 AS capacity_lock_hotfix_installed;
