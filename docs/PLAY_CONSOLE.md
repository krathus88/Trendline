# Google Play release: declarations and listing

What to fill in on Play Console before the first release, and what to check again before each one. Answers follow what the app actually does; if the code changes, change this file with it.

## Before every release

1. Push any new migrations to the real Supabase project (`docs/SETUP.md` section 2).
2. Run the database tests, including the cross-user ones (user A can't read or write user B's rows): `supabase test db`.
3. Run `flutter analyze` and `flutter test`; both must pass with no warnings.
4. Do a security review of everything changed since the last release.
5. If `lib/domain/privacy_policy.dart` changed, run `dart run tool/write_privacy_policy.dart` and commit `docs/PRIVACY.md` (a test fails if they differ). A change in meaning needs `privacyPolicyVersion` raised, so everyone is asked to agree again.

## Privacy policy

- **URL:** `https://github.com/krathus88/Trendline/blob/main/docs/PRIVACY.md` (the repository must be public, and the file on the default branch).
- The same text is in the app: Settings → Privacy and your data → Privacy policy, on the consent screen before onboarding, and on Health Connect's permission screen (Android opens the app on the policy for `ACTION_SHOW_PERMISSIONS_RATIONALE` and `VIEW_PERMISSION_USAGE`; see `MainActivity.kt`).
- Before a public release, replace the contact in `privacyContact` (`lib/domain/privacy_policy.dart`) with an email address for privacy requests. A public issue tracker isn't a suitable place for them.

## App content → Health apps

- **Is it a health app?** Yes.
- **Features:** nutrition and weight management (calorie and macro targets, food logging, meal planning, weight trend).
- It isn't a medical device and makes no medical claims. Onboarding shows a "not medical advice" disclaimer and a health check that stops the app for pregnancy, eating disorders, kidney disease and insulin-treated diabetes.

## Health Connect permissions declaration

Read-only. No write permissions are requested. Keep this list in step with `AndroidManifest.xml` and `HealthConnectSource`.

| Permission | Why |
| --- | --- |
| `READ_WEIGHT` | Imports weigh-ins from the user's scale app to show their weight trend and adjust their calorie targets to it. |
| `READ_BODY_FAT` | Imports body fat recorded with a weigh-in, so the energy estimate can use lean mass when the user turns that on. |
| `READ_LEAN_BODY_MASS` | The same, when the scale records lean mass instead of body fat. |
| `READ_HEALTH_DATA_HISTORY` | Imports readings from before the user connected, so the trend and targets start from their real history rather than empty. |

- **Use case to select:** weight management / nutrition.
- **Limited use:** the data is used only for the trend and targets, never for ads, never sold, and never shared except as the user chooses (read-only sharing of the weight trend: dates and weights only). This is stated in the privacy policy's "Health Connect" section.
- Reviewers may ask for a video of the permission flow: Settings → Health Connect → Connect, then the rationale (privacy policy) from Health Connect's app permissions screen.

## Data safety form

**Collected** (all stored with Supabase in London, encrypted in transit, required for the app to work, not optional unless noted):

| Data type | What | Purpose |
| --- | --- | --- |
| Personal info → Name | Discord username and display name (from sign-in), and the names the user chooses for households and shares | Account management, app functionality |
| Personal info → Email address | From Discord at sign-in | Account management |
| Personal info → User IDs | Discord user ID (sign-in and the invite list) | Account management |
| Health and fitness → Health info | Weight, body fat, lean mass, food log and calorie intake, goal, the health check confirmation | App functionality |
| Health and fitness → Fitness info | Activity level and calorie burn estimates (declare it too: Play may read nutrition logs as fitness data) | App functionality |
| Personal info → Other info | Sex, birth year, height | App functionality |

- **Shared with third parties:** none. Supabase stores the data on the developer's behalf (a service provider, which Play doesn't count as sharing). Open Food Facts receives barcodes and search words only, with nothing identifying the user.
- **Sharing between users** (households, read-only sharing) is started by the user and isn't "sharing" in Play's sense, but the privacy policy describes it.
- **Encrypted in transit:** yes.
- **Users can request deletion:** yes, in the app (Settings → Privacy and your data → Delete my account), which deletes everything immediately.
- **Account deletion web link** (Play requires one for apps with accounts): `https://github.com/krathus88/Trendline/blob/main/docs/DELETE_ACCOUNT.md`. It names the app and developer, gives the steps in the app and a way to ask without it, and says what is deleted and what is kept (household recipes only: Supabase's Free plan has no backups). Moving the project to a paid plan adds daily backups (Pro keeps 7 days): say how long on this page and in the policy's "How long we keep it" before that release (a change in meaning, so raise `privacyPolicyVersion` once the app is released). It's generated with the policy, from `lib/domain/privacy_policy.dart`. Requests that come in without the app are handled by hand: `docs/SETUP.md` section 6.
- **Partial deletion** (deleting some data without the account): yes, anything can be deleted in the app.
- **Ads:** none. **Analytics or crash reporting:** none.

## Target audience and content

- **Target age:** 18 and over only (the profile rejects under-18s).
- **Content rating questionnaire:** no violence, gambling, user-generated public content or chat. Users can share data only with people they choose, by code.

## Store listing

Include these credits in the full description:

> Product data from Open Food Facts (openfoodfacts.org), available under the Open Database License (ODbL).
>
> Basic foods from CoFID (McCance and Widdowson's Composition of Foods Integrated Dataset). Contains public sector information licensed under the Open Government Licence v3.0. Some fibre values from USDA FoodData Central.
>
> Trendline gives estimates, not medical advice. Talk to your GP if you have a health condition.

The same credits are shown in the app, in Settings and in food search results.
