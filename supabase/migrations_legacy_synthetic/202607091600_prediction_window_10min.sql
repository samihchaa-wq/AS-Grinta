-- Migration: aligner la fenêtre de pronostic sur 10 minutes avant le coup d'envoi.
-- Avant : interval '12 hours' (RLS sur match_predictions INSERT/UPDATE).
-- Après  : interval '10 minutes'.
--
-- Les deux politiques concernées sont dans :
--   - 202607090002_rls_policies.sql  (colonne composée match_date + match_time)
--   - 202607090011_timezone_windows_and_normalized_progress.sql  (idem, avec zone Europe/Paris)
-- On remplace les deux RLS policies en DROP + CREATE pour rester idempotent.

-- ── Policy 1 : baseline (sans timezone explicite) ─────────────────────────────
drop policy if exists "Users can insert their own predictions" on match_predictions;
drop policy if exists "Users can update their own predictions" on match_predictions;

create policy "Users can insert their own predictions"
  on match_predictions
  for insert
  to authenticated
  with check (
    profile_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and m.status = 'a_venir'
        and now() > (m.match_date + m.match_time) - interval '6 days'
        and now() < (m.match_date + m.match_time) - interval '10 minutes'
    )
  );

create policy "Users can update their own predictions"
  on match_predictions
  for update
  to authenticated
  using (profile_id = auth.uid())
  with check (
    profile_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and m.status = 'a_venir'
        and now() > (m.match_date + m.match_time) - interval '6 days'
        and now() < (m.match_date + m.match_time) - interval '10 minutes'
    )
  );

-- ── Policy 2 : variante timezone Europe/Paris ─────────────────────────────────
-- (Si votre stack utilise ces politiques nommées différemment, adaptez les noms ci-dessous.)
drop policy if exists "Users can insert predictions in window" on match_predictions;
drop policy if exists "Users can update predictions in window" on match_predictions;

create policy "Users can insert predictions in window"
  on match_predictions
  for insert
  to authenticated
  with check (
    profile_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and m.status = 'a_venir'
        and now() > ((m.match_date + m.match_time) at time zone 'Europe/Paris') - interval '6 days'
        and now() < ((m.match_date + m.match_time) at time zone 'Europe/Paris') - interval '10 minutes'
    )
  );

create policy "Users can update predictions in window"
  on match_predictions
  for update
  to authenticated
  using (profile_id = auth.uid())
  with check (
    profile_id = auth.uid()
    and exists (
      select 1 from matches m
      where m.id = match_id
        and m.status = 'a_venir'
        and now() > ((m.match_date + m.match_time) at time zone 'Europe/Paris') - interval '6 days'
        and now() < ((m.match_date + m.match_time) at time zone 'Europe/Paris') - interval '10 minutes'
    )
  );
