# Proguard rules for BandRoadie release builds
# Keep Flutter and plugin classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Supabase classes
-keep class io.supabase.** { *; }

# Keep Google Fonts
-keep class com.google.** { *; }

# Don't warn about missing classes from optional dependencies
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# --- Flutter Play Core / Deferred Components ---
# These classes are optional (only needed for deferred component loading).
# Add dontwarn to suppress R8 errors for missing Play Core library.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-keep class io.flutter.embedding.android.FlutterPlayStoreSplitApplication { *; }
# --- End Flutter keep rules ---
