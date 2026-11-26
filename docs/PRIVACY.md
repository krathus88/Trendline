# Trendline privacy policy

Version 2, 26 November 2026.

In short:

- Your weight, body measurements and food log are health data. Trendline uses them only to work out your trend, targets and meal plans.
- Everything is stored with Supabase in London. No ads, no analytics, and nothing is ever sold.
- Nobody else sees your data unless you share it, and then only what you choose.
- You can export everything or delete your account at any time in Settings → Privacy and your data.

## Who we are

Trendline is a personal weight-loss and meal-planning app, run by its developer for people they invite. The developer decides how your data is used, so is the data controller under UK GDPR. Contact: https://github.com/krathus88/Trendline (or the person who invited you).

## What we collect

- Your account: the Discord user ID you sign in with, and what Discord passes on at sign-in (username, display name, email address and avatar link). Trendline never sees your Discord password.
- Your profile: sex, birth year, height, activity level, units and other settings.
- Health data: weigh-ins with body fat and lean mass if you add them, that you confirmed none of the health check’s conditions apply (which one applies is never asked), your goal, your food log, which days you marked complete, and the calorie estimates worked out from them.
- Food and planning: the foods and recipes you save, your favourite recipes, likes and dislikes, meal rules, your day schedule, meal plans and meal prep.
- Households and sharing: the names you choose to show, who you share with and what, and invite codes.
- A record of when you agreed to this policy.

We don’t collect your location, contacts, photos, device identifiers or any data about how you use the app.

## Health Connect

On Android you can let Trendline read weight, body fat and lean mass from Health Connect, including readings from before you connected. It never writes to Health Connect and reads nothing else.

Readings from Health Connect are used only to show your weight trend and work out your targets, the same as weigh-ins you enter yourself. They are never used for advertising, never sold, and never passed to anyone else except as described in “Who can see it”. You can turn access off at any time in Health Connect.

## Why, and on what basis

We use your data only to run the app for you: your trend, targets, meal plans and prep, and the households and shares you set up. The lawful basis is providing the service you asked for (UK GDPR article 6(1)(b)). Because weight, body measurements and food intake are health data, we also need your explicit consent (article 9(2)(a)), which the app asks for before you start.

## Where it’s kept

Your data is stored with Supabase, in their London data centre (AWS eu-west-2), and travels encrypted. Access is limited by rules in the database itself, so each account can reach only its own data and what others have shared with it.

On your device, the app keeps your sign-in, and copies of today’s plan, your saved foods and recipes, your recent weigh-ins and the products you looked up by barcode, in encrypted storage, so it opens quickly and still shows them without signal. All of it is deleted when you sign out.

## Who can see it

- You.
- People in your household see the recipes, plans and prep you share with it, including your portion sizes, which hint at your calorie targets. Likes and dislikes, and how many of you starred each shared recipe, are combined for planning without saying whose they are.
- People you share with see only what you switch on for them (your weight trend, daily targets or meal plans), and only until you stop.
- Supabase stores the data for us and can’t use it for anything else. Discord handles sign-in only and gets nothing from the app.
- Open Food Facts receives the barcodes you scan and the words you search for, to look up products. Nothing that identifies you is sent with them.

There are no ads, analytics or crash-reporting services in the app, and your data is never sold.

## How long we keep it

Until you delete it, or delete your account. Deleting your account removes everything at once, including your place on the invite list. Recipes you shared with a household stay with the household. Supabase keeps no backups of Trendline’s database, so no copy remains after deletion.

## Your rights

- See and copy your data: Settings → Privacy and your data → Export my data saves all of it as a JSON file, or your weigh-ins and food log as spreadsheets (CSV).
- Correct it: edit or delete anything in the app.
- Delete it: Settings → Privacy and your data → Delete my account. If you can’t open the app, see https://github.com/krathus88/Trendline/blob/main/docs/DELETE_ACCOUNT.md.
- Withdraw your consent: deleting your account does this. To stop Health Connect imports only, turn Trendline’s access off in Health Connect.
- Complain: you can contact the Information Commissioner’s Office (ico.org.uk) if you’re unhappy with how your data is handled.

## Age

Trendline is for adults (18 and over) only.

## Not medical advice

Trendline gives estimates, not medical advice. Talk to your GP if you have a health condition.

## Changes

If this policy changes in a way that matters, the version number goes up and the app asks you to agree again before you carry on.
