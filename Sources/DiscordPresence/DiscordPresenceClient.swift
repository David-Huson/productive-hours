import ActivityCore
import DiscordRPCBridge
import Foundation

@MainActor
public final class DiscordPresenceClient {
    private var connected = false
    private var applicationId = ""
    private var detailsBuffer: [CChar] = []
    private var stateBuffer: [CChar] = []
    private var largeImageKeyBuffer: [CChar] = Array("worktempo".utf8CString)
    private var largeImageTextBuffer: [CChar] = []
    private var smallImageKeyBuffer: [CChar] = []

    public init() {}

    public func configure(enabled: Bool, applicationId: String) {
        let id = applicationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !id.isEmpty, id.allSatisfy(\.isNumber) else {
            shutdown()
            return
        }
        if connected, self.applicationId == id { return }
        shutdown()
        self.applicationId = id
        id.withCString { Discord_Initialize($0, nil, 0, nil) }
        connected = true
    }

    public func update(presence: DiscordPresenceFormatted?, tracking: Bool) {
        guard connected else { return }
        Discord_RunCallbacks()
        guard tracking, let copy = presence else {
            Discord_ClearPresence()
            return
        }
        store(copy.details, in: &detailsBuffer)
        store(copy.state, in: &stateBuffer)
        store(copy.largeImageText, in: &largeImageTextBuffer)
        if copy.smallImageKey.isEmpty {
            smallImageKeyBuffer = []
        } else {
            store(copy.smallImageKey, in: &smallImageKeyBuffer)
        }
        var presence = DiscordRichPresence()
        presence.statusDisplayType = Int8(DISCORD_STATUS_DISPLAY_DETAILS)
        if let start = copy.startTimestamp { presence.startTimestamp = start }
        detailsBuffer.withUnsafeBufferPointer { details in
            stateBuffer.withUnsafeBufferPointer { state in
                largeImageKeyBuffer.withUnsafeBufferPointer { imageKey in
                    largeImageTextBuffer.withUnsafeBufferPointer { imageText in
                        presence.details = details.baseAddress
                        presence.state = state.baseAddress
                        presence.largeImageKey = imageKey.baseAddress
                        presence.largeImageText = imageText.baseAddress
                        if !smallImageKeyBuffer.isEmpty {
                            smallImageKeyBuffer.withUnsafeBufferPointer { smallKey in
                                presence.smallImageKey = smallKey.baseAddress
                                Discord_UpdatePresence(&presence)
                            }
                        } else {
                            Discord_UpdatePresence(&presence)
                        }
                    }
                }
            }
        }
    }

    public func shutdown() {
        guard connected else { return }
        Discord_RunCallbacks()
        Discord_ClearPresence()
        Discord_Shutdown()
        connected = false
        applicationId = ""
        detailsBuffer = []
        stateBuffer = []
        largeImageTextBuffer = []
        smallImageKeyBuffer = []
    }

    private func store(_ value: String, in buffer: inout [CChar]) {
        buffer = Array(value.utf8CString)
    }
}
