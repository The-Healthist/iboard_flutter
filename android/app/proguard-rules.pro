# Keep Flutter and plugin classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep video_player plugin and ExoPlayer/Media3 (avoid stripping reflection-used APIs)
-keep class io.flutter.plugins.videoplayer.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }
-dontwarn com.google.android.exoplayer2.**
-dontwarn androidx.media3.**

# Keep Kotlin stdlib and coroutines
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# Keep OkHttp/Okio if present
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep Logger (or any logging) to prevent method stripping if used via reflection
-keep class **.Logger { *; }

# Keep application classes
-keep class com.ismart.iboard.iboard_app.** { *; }

# Keep annotations and signatures
-keepattributes *Annotation*
-keepattributes Signature, InnerClasses, EnclosingMethod

# If you see mapping-related crashes, consider disabling optimization for media
#-dontoptimize
