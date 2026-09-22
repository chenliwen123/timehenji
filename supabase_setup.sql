-- 时间痕迹：Supabase 初始化脚本
-- 在 Supabase 控制台的 SQL Editor 中执行整个文件，可重复执行。
-- 执行后还需要在 Authentication -> Providers 开启 Anonymous Sign-Ins。
--
-- 本项目只有这一张表。照片本体与照片索引都存在设备本地，不上传云端。
-- 如果你的项目是从旧的「我的衣橱」版本建的，先执行 supabase_cleanup_legacy.sql。
--
-- 四个日期都允许为 NULL：表示用户还没填写该事件，App 不会生成对应卡片，
-- 也不设任何默认值——过去这里写死的是开发者本人的真实日期。
create table if not exists public.life_settings (
  owner_id uuid primary key default auth.uid()
    references auth.users(id) on delete cascade,
  birth_date date,
  marriage_date date,
  graduation_date date,
  work_date date,
  custom_cards jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

-- 旧库补列：App 在读到缺失列时会降级查询，但建议直接执行本脚本补齐。
alter table public.life_settings
  add column if not exists custom_cards jsonb not null default '[]'::jsonb;

-- 从旧版本升级上来的库，日期列曾是 NOT NULL，需要放开约束才能存 NULL。
-- 全新建库时下面的语句不会改变任何东西。
alter table public.life_settings
  alter column birth_date drop not null,
  alter column marriage_date drop not null,
  alter column graduation_date drop not null,
  alter column work_date drop not null;

-- 每次更新自动刷新 updated_at（表默认值只在插入时生效）。
create or replace function public.touch_life_settings()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists life_settings_touch_updated_at on public.life_settings;
create trigger life_settings_touch_updated_at
  before update on public.life_settings
  for each row execute function public.touch_life_settings();

alter table public.life_settings enable row level security;
grant select, insert, update, delete on public.life_settings to authenticated;

drop policy if exists "life_settings_select_own" on public.life_settings;
create policy "life_settings_select_own"
on public.life_settings for select to authenticated
using (owner_id = (select auth.uid()));

drop policy if exists "life_settings_insert_own" on public.life_settings;
create policy "life_settings_insert_own"
on public.life_settings for insert to authenticated
with check (owner_id = (select auth.uid()));

drop policy if exists "life_settings_update_own" on public.life_settings;
create policy "life_settings_update_own"
on public.life_settings for update to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

drop policy if exists "life_settings_delete_own" on public.life_settings;
create policy "life_settings_delete_own"
on public.life_settings for delete to authenticated
using (owner_id = (select auth.uid()));
