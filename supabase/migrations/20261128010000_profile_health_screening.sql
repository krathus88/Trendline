-- When the user confirmed that none of the conditions that need medical
-- supervision apply to them (pregnancy or breastfeeding, an eating disorder,
-- kidney disease, diabetes treated with insulin or tablets that can cause
-- low blood sugar). Only this date is stored: never which condition applied,
-- since that would be health data the app has no need to keep.

alter table public.profiles
  add column health_screened_at timestamptz;
