package dev.android.anotheriptvplayer.networking

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Decoders that mirror iOS `decodeFlexibleStringIfPresent` /
 * `decodeFlexibleIntIfPresent`.
 *
 * Xtream servers are notoriously inconsistent: the same field can come back
 * as a JSON string on one server and as a number on another (`"123"` vs
 * `123`), or null, or omitted entirely. Strict decoding fails on real-world
 * data; these serializers normalise into a single Kotlin type and return
 * `null` when nothing usable is there.
 *
 * Applied with `@Serializable(with = FlexibleString::class)` on the field.
 */
internal object FlexibleString : KSerializer<String?> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("FlexibleString", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String? {
        val input = decoder as? JsonDecoder ?: return null
        val element = input.decodeJsonElement()
        if (element is JsonNull) return null
        val prim = element as? JsonPrimitive ?: return null
        // contentOrNull would give "null" for JsonNull strings; we already
        // filtered JsonNull above, so .content is the right surface.
        return when {
            prim.isString -> prim.content.takeIf { it.isNotEmpty() }
            else -> prim.content // numbers / booleans rendered as text
        }
    }

    override fun serialize(encoder: Encoder, value: String?) {
        val output = encoder as? JsonEncoder
            ?: error("FlexibleString only supports JSON encoding.")
        if (value == null) output.encodeJsonElement(JsonNull) else output.encodeString(value)
    }
}

/**
 * Accepts an int, a numeric string, a double (truncated), or null. Mirrors
 * iOS `decodeFlexibleIntIfPresent`.
 */
internal object FlexibleInt : KSerializer<Int?> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("FlexibleInt", PrimitiveKind.INT)

    override fun deserialize(decoder: Decoder): Int? {
        val input = decoder as? JsonDecoder ?: return null
        val element = input.decodeJsonElement()
        if (element is JsonNull) return null
        val prim = element as? JsonPrimitive ?: return null
        prim.intOrNull?.let { return it }
        prim.longOrNull?.let { return it.toInt() }
        prim.doubleOrNull?.let { return it.toInt() }
        if (prim.isString) {
            val text = prim.content.trim()
            text.toIntOrNull()?.let { return it }
            text.toDoubleOrNull()?.let { return it.toInt() }
        }
        prim.booleanOrNull?.let { return if (it) 1 else 0 }
        return null
    }

    override fun serialize(encoder: Encoder, value: Int?) {
        val output = encoder as? JsonEncoder
            ?: error("FlexibleInt only supports JSON encoding.")
        if (value == null) output.encodeJsonElement(JsonNull) else output.encodeInt(value)
    }
}

/**
 * Accepts a double, an int, or a numeric string. Returns null on anything
 * else. iOS uses `try? container?.decodeIfPresent(Double.self, ...)` for
 * `rating_5based`/`vote_average` — same intent, but more permissive about
 * stringified numbers because real responses include them.
 */
internal object FlexibleDouble : KSerializer<Double?> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("FlexibleDouble", PrimitiveKind.DOUBLE)

    override fun deserialize(decoder: Decoder): Double? {
        val input = decoder as? JsonDecoder ?: return null
        val element = input.decodeJsonElement()
        if (element is JsonNull) return null
        val prim = element as? JsonPrimitive ?: return null
        prim.doubleOrNull?.let { return it }
        if (prim.isString) return prim.content.trim().toDoubleOrNull()
        return null
    }

    override fun serialize(encoder: Encoder, value: Double?) {
        val output = encoder as? JsonEncoder
            ?: error("FlexibleDouble only supports JSON encoding.")
        if (value == null) output.encodeJsonElement(JsonNull) else output.encodeDouble(value)
    }
}
