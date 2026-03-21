import Foundation
import MultipeerConnectivity
import UIKit
import PhotoTagsCore

@MainActor
final class LANTransferService: NSObject, ObservableObject {
    @Published private(set) var nearbyPeers: [MCPeerID] = []

    var onReceiveEnvelopeData: ((Data, MCPeerID) -> Void)?
    var onStateMessage: ((String) -> Void)?

    private let serviceType = "phototags-sync"
    private let myPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    init(deviceName: String = UIDevice.current.name) {
        self.myPeerID = MCPeerID(displayName: deviceName)
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        self.browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        super.init()

        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    var deviceName: String {
        myPeerID.displayName
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        onStateMessage?("局域网发现已开启。")
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        nearbyPeers = []
        onStateMessage?("局域网发现已关闭。")
    }

    func send(envelopeData data: Data, to peer: MCPeerID) throws {
        guard session.connectedPeers.contains(peer) else {
            throw NSError(domain: "LANTransfer", code: 1, userInfo: [NSLocalizedDescriptionKey: "目标设备未连接"])
        }
        try session.send(data, toPeers: [peer], with: .reliable)
        onStateMessage?("已发送到 \(peer.displayName)")
    }
}

extension LANTransferService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            let text: String
            switch state {
            case .connected: text = "已连接：\(peerID.displayName)"
            case .connecting: text = "连接中：\(peerID.displayName)"
            case .notConnected: text = "已断开：\(peerID.displayName)"
            @unknown default: text = "连接状态未知：\(peerID.displayName)"
            }
            onStateMessage?(text)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            onReceiveEnvelopeData?(data, peerID)
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}

extension LANTransferService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor in
            onStateMessage?("广播失败：\(error.localizedDescription)")
        }
    }
}

extension LANTransferService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor in
            if !nearbyPeers.contains(peerID) {
                nearbyPeers.append(peerID)
            }
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            nearbyPeers.removeAll { $0 == peerID }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            onStateMessage?("扫描失败：\(error.localizedDescription)")
        }
    }
}
