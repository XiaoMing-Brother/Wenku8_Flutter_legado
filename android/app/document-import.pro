# PDFBox's JPX codec is an optional JCenter-only dependency. The importer
# rejects JPX images explicitly before decoding; other PDF filters stay live.
-dontwarn com.gemalto.jp2.JP2Decoder
-dontwarn com.gemalto.jp2.JP2Encoder

# POI HWPF reads binary Word text/raster bytes only. Java2D metafile geometry
# and GenericRecord JSON/debug rendering are desktop-only, not reader paths.
-dontwarn java.awt.**
# Log4j's optional OSGi discovery and compile-time annotations are not an
# Android logging backend; the API falls back to its built-in simple logger.
-dontwarn org.osgi.framework.**
-dontwarn aQute.bnd.annotation.**
-dontwarn edu.umd.cs.findbugs.annotations.**

# Book source rules run JavaScript through Rhino and query JSONPath at
# runtime, so keep the engine classes from being stripped or renamed.
-keep class org.mozilla.javascript.** { *; }
-keep class com.jayway.jsonpath.** { *; }
-dontwarn org.mozilla.javascript.**
-dontwarn jakarta.json.**
-dontwarn org.apache.tapestry5.**
-dontwarn org.codehaus.jettison.**
-dontwarn com.google.gson.**
-dontwarn com.fasterxml.jackson.**
