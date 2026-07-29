package com.bandroadie.app

import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun attachBaseContext(newBase: Context) {
        val configuration = Configuration(newBase.resources.configuration)
        configuration.uiMode = (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            Configuration.UI_MODE_NIGHT_YES
        super.attachBaseContext(newBase.createConfigurationContext(configuration))
    }
}
