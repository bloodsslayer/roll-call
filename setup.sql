-- Roll Call: database setup
-- Run this once in Supabase → SQL Editor → New query → Run

create extension if not exists pgcrypto;

create table class_sessions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  roster text[] not null default '{}',
  is_current boolean not null default false,
  created_at timestamptz not null default now()
);

create table attendance (
  id bigint generated always as identity primary key,
  session_id uuid not null references class_sessions(id) on delete cascade,
  name text not null,
  device_token text not null,
  marked_at timestamptz not null default now(),
  unique (session_id, name),          -- a name can only be marked once per session
  unique (session_id, device_token)   -- a device can only mark once per session
);

alter table class_sessions enable row level security;
alter table attendance enable row level security;

-- Anyone with the link can read the roster and the live attendance list.
create policy "public can read sessions" on class_sessions for select using (true);
create policy "public can read attendance" on attendance for select using (true);

-- No direct insert/update/delete policies are created, so the public (anon) key
-- can never write straight into these tables. The only way to add an attendance
-- row is through the function below, which enforces the rules server-side.

create or replace function mark_attendance(p_session_id uuid, p_name text, p_device_token text)
returns text
language plpgsql
security definer
as $$
begin
  if not exists (
    select 1 from class_sessions
    where id = p_session_id and p_name = any(roster)
  ) then
    return 'invalid_name';
  end if;

  begin
    insert into attendance (session_id, name, device_token)
    values (p_session_id, p_name, p_device_token);
    return 'ok';
  exception when unique_violation then
    if exists (
      select 1 from attendance
      where session_id = p_session_id and device_token = p_device_token
    ) then
      return 'device_already_marked';
    else
      return 'name_already_marked';
    end if;
  end;
end;
$$;

grant execute on function mark_attendance(uuid, text, text) to anon;

-- ---------------------------------------------------------------------
-- Start your first session (edit the name and roster, then run this too)
-- ---------------------------------------------------------------------
update class_sessions set is_current = false;

insert into class_sessions (name, roster, is_current)
values (
  'First session',
  array['Alex','Jordan','Sam','Taylor'],
  true
);
