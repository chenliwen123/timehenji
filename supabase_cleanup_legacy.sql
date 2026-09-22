-- 时间痕迹：清理已废弃的数据库对象
--
-- 分三段，按需执行。都在 Supabase 控制台的 SQL Editor 里跑。
-- A、C 会永久删除对象，无法回滚：想留档就先在控制台备份，或跳过对应段落。
-- 全新项目三段都不需要，只执行 supabase_setup.sql。

-- ── A. 农历列：从旧版本升级上来的库都要执行一次 ──────────────────────
-- App 不再读写这些列。阴历规则已由自定义卡片的 date_entries.calendar 承担，
-- 这 5 列在代码里没有任何读取方。
alter table public.life_settings
  drop column if exists spouse_birthday_lunar_month,
  drop column if exists spouse_birthday_lunar_day,
  drop column if exists registration_lunar_year,
  drop column if exists registration_lunar_month,
  drop column if exists registration_lunar_day;

-- ── B. 旧版本写死的"默认日期"：改成可空之后清一次 ──────────────────
-- 早期版本把开发者本人的生日、结婚日等当成默认值，每次保存都会同步进表里。
-- 现在日期可以为 NULL，但已存的值不会自己消失，会继续冒充用户自己填的日期。
-- 先确认哪些是真实填写的，再把要清掉的日期改成 NULL。
-- 注意：日期列的 NOT NULL 约束由 supabase_setup.sql 负责放开，这里只清数据。

select owner_id,
       birth_date,
       marriage_date,
       graduation_date,
       work_date,
       updated_at
from public.life_settings
order by updated_at desc;

-- 确认无误后手动执行（默认注释，避免误删你真正填写的日期）：
-- update public.life_settings
--   set birth_date = null,
--       marriage_date = null,
--       graduation_date = null,
--       work_date = null;

-- ── C. 衣橱遗留：仅项目最初由「我的衣橱」建库时执行 ──────────────────
-- 下列对象当前版本的 App 完全不使用。

drop table if exists public.clothes;

delete from storage.objects
where bucket_id = 'wardrobe-images';

delete from storage.buckets
where id = 'wardrobe-images';

drop policy if exists "wardrobe_images_select_own" on storage.objects;
drop policy if exists "wardrobe_images_insert_own" on storage.objects;
drop policy if exists "wardrobe_images_delete_own" on storage.objects;
