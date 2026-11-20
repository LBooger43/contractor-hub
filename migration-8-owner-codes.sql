-- Owner invite codes: nobody can start a NEW business without a code from Leif.
-- Existing businesses (Rosa, Wayne, Chepe) and crew joining with a crew code are not affected.
create table if not exists owner_codes (
  code text primary key,
  uses_left int not null default 1 check (uses_left >= 0),
  note text not null default '',
  created_at timestamptz not null default now()
);
alter table owner_codes enable row level security;   -- no policies: only the sign-up function can read it

-- Codes are added straight in Supabase (never saved in this public repo):
--   insert into owner_codes (code, uses_left, note) values ('XXXX-XXXX-XXXX', 1, 'note');

-- New sign-up path: needs a code. p_app picks the owner's color.
create or replace function create_business_v2(p_code text, p_business text, p_name text, p_phone text default '', p_app text default 'limpiempo')
returns uuid language plpgsql security definer set search_path = public as $$
declare b uuid; ok int;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if exists (select 1 from members where user_id = auth.uid()) then raise exception 'Already in a business'; end if;
  update owner_codes set uses_left = uses_left - 1 where upper(code) = upper(trim(coalesce(p_code,''))) and uses_left > 0;
  get diagnostics ok = row_count;
  if ok = 0 then raise exception 'BAD_CODE'; end if;
  insert into businesses (name, phone) values (trim(p_business), coalesce(p_phone,'')) returning id into b;
  insert into members (user_id, business_id, name, role, color, phone)
    values (auth.uid(), b, trim(p_name), 'owner', case when p_app = 'chub' then '#1F6FEB' else '#D6245E' end, coalesce(p_phone,''));
  return b;
end $$;
grant execute on function create_business_v2(text, text, text, text, text) to authenticated;

-- Close the old no-code door.
create or replace function create_business(p_business text, p_name text, p_phone text default '')
returns uuid language plpgsql security definer set search_path = public as $$
begin raise exception 'BAD_CODE'; end $$;

-- To add more codes later (Supabase › SQL Editor):
--   insert into owner_codes (code, uses_left, note) values ('HUB-NEW1-CODE', 1, 'for Mike');
-- To see which codes are left:
--   select code, uses_left, note from owner_codes order by created_at;
