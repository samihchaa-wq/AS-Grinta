delete from public.profile_badge_seen
where badge_code in ('doubles__10', 'doubles__20', 'doubles__30', 'doubles__50');

delete from public.profile_badges pb
using public.badges b
where pb.badge_id = b.id
  and b.code in ('doubles__10', 'doubles__20', 'doubles__30', 'doubles__50');

delete from public.badges
where code in ('doubles__10', 'doubles__20', 'doubles__30', 'doubles__50');
