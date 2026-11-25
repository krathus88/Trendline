package com.krathus.trendline

import io.flutter.embedding.android.FlutterFragmentActivity

// A fragment activity: Health Connect's permission screen needs one.
class MainActivity : FlutterFragmentActivity() {
    // Health Connect opens the app to show why it wants access. Those
    // launches start on the privacy policy (see privacyPolicyRoute in
    // lib/app.dart) instead of the app.
    override fun getInitialRoute(): String? = when (intent?.action) {
        "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE",
        "android.intent.action.VIEW_PERMISSION_USAGE" -> "/privacy-policy"
        else -> super.getInitialRoute()
    }
}
