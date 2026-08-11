update public.badges
set color = case color
  when '#6E7A86' then '#7A858D'
  when '#B87333' then '#CD7F32'
  when '#C4CBD4' then '#C0C0C0'
  when '#E3B23C' then '#D4AF37'
  when '#5FC9D9' then '#B9F2FF'
  else color
end
where color in ('#6E7A86', '#B87333', '#C4CBD4', '#E3B23C', '#5FC9D9');
