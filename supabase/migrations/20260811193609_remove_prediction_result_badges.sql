-- Remove all badges tied to counts of correct match results or exact scores.
-- Prediction statistics themselves are intentionally preserved.

DELETE FROM public.profile_badge_seen
WHERE badge_code LIKE 'pred_good_result__%'
   OR badge_code LIKE 'pred_exact_score__%'
   OR badge_code IN (
     SELECT code
     FROM public.badges
     WHERE metric IN ('pred_good_result', 'pred_exact_score', 'good_bets', 'exact_scores')
   );

DELETE FROM public.profile_badges pb
USING public.badges b
WHERE pb.badge_id = b.id
  AND (
    b.metric IN ('pred_good_result', 'pred_exact_score', 'good_bets', 'exact_scores')
    OR b.code LIKE 'pred_good_result__%'
    OR b.code LIKE 'pred_exact_score__%'
  );

DELETE FROM public.badges
WHERE metric IN ('pred_good_result', 'pred_exact_score', 'good_bets', 'exact_scores')
   OR code LIKE 'pred_good_result__%'
   OR code LIKE 'pred_exact_score__%';
