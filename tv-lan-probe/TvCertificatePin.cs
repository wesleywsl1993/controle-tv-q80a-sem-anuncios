using System;
using System.Net.Security;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

// Used only by the ClientWebSocket opened for the configured private TV IP:8002.
public sealed class TvCertificatePin
{
    private readonly string savedFingerprint;
    public string ObservedFingerprint { get; private set; } = "";
    public string RejectionReason { get; private set; } = "";

    public TvCertificatePin(string savedFingerprint)
    {
        this.savedFingerprint = savedFingerprint ?? "";
    }

    public bool Validate(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors errors)
    {
        if (certificate == null)
        {
            RejectionReason = "A TV não apresentou certificado.";
            return false;
        }
        using (var leaf = new X509Certificate2(certificate))
        {
            var now = DateTime.UtcNow;
            if (now < leaf.NotBefore.ToUniversalTime() || now > leaf.NotAfter.ToUniversalTime())
            {
                RejectionReason = "Certificado da TV fora do período de validade.";
                return false;
            }
            var fingerprint = Convert.ToHexString(SHA256.HashData(leaf.RawData));
            ObservedFingerprint = fingerprint;
            if (!string.IsNullOrEmpty(savedFingerprint) &&
                !string.Equals(savedFingerprint, fingerprint, StringComparison.OrdinalIgnoreCase))
            {
                RejectionReason = "Certificado da TV mudou. A conexão foi recusada.";
                return false;
            }
            // The TV's certificate can be self-signed and may not name the IP.
            // First use is trust-on-first-use; later connections require the saved fingerprint.
            return true;
        }
    }
}
