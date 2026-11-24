-- Whether the user does regular strength training. It raises the protein
-- target, since training is what builds and keeps muscle.

alter table public.profiles
  add column strength_training boolean not null default false;
