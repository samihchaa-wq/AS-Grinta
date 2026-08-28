begin;

-- Recalibrage des paliers de passes décisives sur une saison :
-- 5 / 10 / 15 / 20 au lieu de 3 / 5 / 10 / 15.
--
-- Les codes historiques sont volontairement conservés : ils servent
-- d'identifiants stables au catalogue et permettent de garder les mêmes
-- lignes (image_url, badge_id, profile_badges) sans recréer les badges.
update public.badges
set
  threshold = case code
    when 'assists_season__3' then 5
    when 'assists_season__5' then 10
    when 'assists_season__10' then 15
    when 'assists_season__15' then 20
    else threshold
  end,
  description = case code
    when 'assists_season__3'
      then 'Délivrer 5 passes décisives au cours d’une même saison.'
    when 'assists_season__5'
      then 'Délivrer 10 passes décisives au cours d’une même saison.'
    when 'assists_season__10'
      then 'Délivrer 15 passes décisives au cours d’une même saison.'
    when 'assists_season__15'
      then 'Délivrer 20 passes décisives au cours d’une même saison.'
    else description
  end
where metric = 'assists_season'
  and code in (
    'assists_season__3',
    'assists_season__5',
    'assists_season__10',
    'assists_season__15'
  );

commit;
