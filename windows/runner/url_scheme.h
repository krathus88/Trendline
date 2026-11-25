#ifndef RUNNER_URL_SCHEME_H_
#define RUNNER_URL_SCHEME_H_

// The custom URL scheme Discord sign-in returns to. Must match the scheme of
// SupabaseConfig.authRedirectUrl and the redirect URLs allowed in Supabase.
inline constexpr wchar_t kUrlScheme[] = L"com.krathus.trendline";

// Registers kUrlScheme for the current user (HKCU, no admin rights), pointing
// at this executable, so the browser can hand the sign-in callback back to the
// app. Rewritten on every launch so it follows the app if it moves. Returns
// false if the registry couldn't be written; sign-in then can't return to the
// app, but everything else still works.
bool RegisterUrlScheme();

#endif  // RUNNER_URL_SCHEME_H_
