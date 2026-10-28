import Foundation
import Security
import CryptoKit

/// Trust is scoped to one user-selected private IPv4 host on port 8002.
/// The first certificate is pinned locally; a later certificate change is rejected.
final class TVSessionDelegate: NSObject, URLSessionDelegate, URLSessionWebSocketDelegate, URLSessionTaskDelegate {
    let host: String
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?

    init(host: String) {
        self.host = host
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard TVProtocol.isPrivateIPv4(host),
              space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host == host, space.port == 8002,
              let trust = space.serverTrust,
              let leaf = SecTrustGetCertificateAtIndex(trust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Samsung's local certificate may be self-signed and may not name the IP.
        // Validate its dates/chain using that leaf as the only anchor, then pin it.
        guard SecTrustSetPolicies(trust, SecPolicyCreateBasicX509()) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [leaf] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let data = SecCertificateCopyData(leaf) as Data
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined()
        if let previous = PairingStore.certificatePin(for: host) {
            guard previous == fingerprint else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        } else if !PairingStore.saveCertificatePin(fingerprint, for: host) {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol selectedProtocol: String?) {
        onOpen?()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        onClose?()
    }
}
