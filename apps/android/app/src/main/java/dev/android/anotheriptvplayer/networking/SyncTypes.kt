package dev.android.anotheriptvplayer.networking

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

/**
 * Wire types for the self-hosted sync-server API (see
 * `services/sync-server/README.md` in the repo root for the full contract).
 */

@Serializable
data class SyncPushItem(
    val kind: String,
    val key: String,
    val payload: JsonElement,
    val updatedAt: Long,
    val deleted: Boolean,
)

@Serializable
internal data class SyncPushRequest(val items: List<SyncPushItem>)

@Serializable
data class SyncPushResultItem(
    val kind: String,
    val key: String,
    val status: String,
)

@Serializable
internal data class SyncPushResponse(val results: List<SyncPushResultItem>)

@Serializable
data class SyncPullItem(
    val kind: String,
    val key: String,
    val payload: JsonElement,
    val updatedAt: Long,
    val deleted: Boolean,
)

@Serializable
data class SyncPullResponse(
    val items: List<SyncPullItem>,
    val cursor: Long,
    val hasMore: Boolean,
)

@Serializable
internal data class SyncRegisterRequest(val username: String, val password: String)

@Serializable
internal data class SyncTokenRequest(
    val username: String,
    val password: String,
    val deviceName: String,
)

@Serializable
data class SyncTokenResponse(
    val token: String,
    val deviceId: Long,
    val deviceName: String,
)

@Serializable
data class SyncDeviceInfo(
    val id: Long,
    val deviceName: String,
    val createdAt: Long,
    val lastSeenAt: Long,
    val revoked: Boolean,
    val current: Boolean,
)

@Serializable
internal data class SyncDevicesResponse(val devices: List<SyncDeviceInfo>)

@Serializable
internal data class SyncErrorResponse(val error: String? = null)

/** `progress` kind payload. `seriesId` is always a string on the wire so it
 * round-trips losslessly across platforms whose native id type differs. */
@Serializable
data class SyncProgressPayload(
    val positionSeconds: Double,
    val durationSeconds: Double,
    val title: String? = null,
    val secondaryTitle: String? = null,
    @SerialName("imageURL") val imageUrl: String? = null,
    val containerExtension: String? = null,
    val seriesId: String? = null,
)

sealed class SyncApiException(message: String, cause: Throwable? = null) :
    RuntimeException(message, cause) {

    class NotConfigured : SyncApiException("Sync server is not configured")
    class NotSignedIn : SyncApiException("Not signed in to a sync server")
    class Network(cause: Throwable) : SyncApiException("Network error: ${cause.message}", cause)
    class Server(val status: Int, serverMessage: String?) :
        SyncApiException(serverMessage ?: "Sync server returned HTTP $status")
}
