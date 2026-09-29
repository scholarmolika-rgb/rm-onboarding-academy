-- CI only: minimal stand-ins for Supabase's auth schema and roles
do $$ begin create role authenticated; exception when others then null; end $$;
do $$ begin create role anon; exception when others then null; end $$;
create schema if not exists auth;
create table if not exists auth.users(id uuid primary key default gen_random_uuid(), email text);
create or replace function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('test.uid', true),'')::uuid $$;
