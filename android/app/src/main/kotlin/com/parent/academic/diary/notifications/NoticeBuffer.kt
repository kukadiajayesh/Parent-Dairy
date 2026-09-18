package com.parent.academic.diary.notifications

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The bounded ring buffer of captured notifications and the opt-in package
 * set, both in their own `SharedPreferences` files.
 *
 * Two files rather than one: the listener reads the watched set on *every*
 * posted notification and must not deserialise the whole buffer to do so.
 * Both are written by the Dart side through the plugin and read here without
 * any IPC, because the service runs when no Flutter engine exists.
 */
object NoticeBuffer {
    private const val BUFFER_FILE = "diary_notice_buffer"
    private const val WATCH_FILE = "diary_notice_watch"
    private const val KEY_ENTRIES = "entries"
    private const val KEY_PACKAGES = "packages"
    private const val KEY_CONNECTED = "listenerConnected"
    private const val KEY_LAST_CAPTURE = "lastCaptureAt"

    /** Prompt 03 §A.5: 500 entries, oldest dropped first. */
    const val CAPACITY = 500

    /** Prompt 03 §F: bodies are stored up to 4000 chars with a `truncated` flag. */
    const val MAX_BODY = 4000

    private val lock = Any()

    private fun buffer(context: Context): SharedPreferences =
        context.getSharedPreferences(BUFFER_FILE, Context.MODE_PRIVATE)

    private fun watch(context: Context): SharedPreferences =
        context.getSharedPreferences(WATCH_FILE, Context.MODE_PRIVATE)

    // ── watched packages ────────────────────────────────────────────────

    fun watchedPackages(context: Context): Set<String> =
        watch(context).getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()

    fun setWatchedPackages(context: Context, packages: Collection<String>) {
        // A fresh HashSet: SharedPreferences may hand back the same instance it
        // stored, and mutating that is undefined behaviour.
        watch(context).edit().putStringSet(KEY_PACKAGES, HashSet(packages)).apply()
    }

    // ── listener availability ───────────────────────────────────────────

    fun setListenerConnected(context: Context, connected: Boolean) {
        watch(context).edit().putBoolean(KEY_CONNECTED, connected).apply()
    }

    fun isListenerConnected(context: Context): Boolean =
        watch(context).getBoolean(KEY_CONNECTED, false)

    fun lastCaptureAt(context: Context): Long = watch(context).getLong(KEY_LAST_CAPTURE, 0L)

    // ── entries ─────────────────────────────────────────────────────────

    /**
     * Appends [entry], replacing a buffered entry that shares its `key` (an
     * Android update of the same notification) or its `hash` (a re-post of
     * the same text). Keeps the longer body when replacing, since updates
     * usually expand a collapsed message rather than change it.
     */
    fun append(context: Context, entry: JSONObject) {
        synchronized(lock) {
            val entries = read(context)
            val key = entry.optString("key")
            val hash = entry.optString("hash")
            var replaced = false
            for (i in 0 until entries.length()) {
                val existing = entries.getJSONObject(i)
                val sameKey = key.isNotEmpty() && existing.optString("key") == key
                val sameHash = hash.isNotEmpty() && existing.optString("hash") == hash
                if (!sameKey && !sameHash) continue
                if (entry.optString("body").length >= existing.optString("body").length) {
                    entries.put(i, entry)
                }
                replaced = true
                break
            }
            if (!replaced) entries.put(entry)
            // Drop from the front until within capacity — the oldest captures
            // are the ones the parent is least likely to still care about.
            while (entries.length() > CAPACITY) entries.remove(0)
            write(context, entries)
            watch(context).edit().putLong(KEY_LAST_CAPTURE, System.currentTimeMillis()).apply()
        }
    }

    fun size(context: Context): Int = synchronized(lock) { read(context).length() }

    /** Returns every buffered entry as a list of maps and clears the buffer. */
    fun drain(context: Context): List<Map<String, Any?>> = synchronized(lock) {
        val entries = read(context)
        val out = ArrayList<Map<String, Any?>>(entries.length())
        for (i in 0 until entries.length()) {
            val o = entries.getJSONObject(i)
            out.add(
                mapOf(
                    "packageName" to o.optString("packageName"),
                    "appLabel" to o.optString("appLabel"),
                    "title" to o.optString("title"),
                    "body" to o.optString("body"),
                    "postedAt" to o.optLong("postedAt"),
                    "key" to o.optString("key"),
                    "category" to o.optString("category", ""),
                    "hash" to o.optString("hash"),
                    "truncated" to o.optBoolean("truncated", false),
                )
            )
        }
        write(context, JSONArray())
        out
    }

    private fun read(context: Context): JSONArray {
        val raw = buffer(context).getString(KEY_ENTRIES, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            // A corrupt buffer is dropped rather than crashing the listener
            // service; the next notification starts a clean one.
            JSONArray()
        }
    }

    private fun write(context: Context, entries: JSONArray) {
        buffer(context).edit().putString(KEY_ENTRIES, entries.toString()).apply()
    }

    // ── dedupe hash ─────────────────────────────────────────────────────

    /**
     * `sha1(packageName|title|body|yyyy-MM-dd)` — device-independent, so the
     * same notice captured on two phones lands on one Firestore document.
     * The Dart side computes the identical hash before every write.
     */
    fun hashFor(packageName: String, title: String, body: String, postedAt: Long): String {
        val day = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(postedAt))
        val input = "$packageName|$title|$body|$day"
        val digest = MessageDigest.getInstance("SHA-1").digest(input.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}
