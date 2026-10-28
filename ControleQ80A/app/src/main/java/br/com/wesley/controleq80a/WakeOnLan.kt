package br.com.wesley.controleq80a

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.util.Collections

object WakeOnLan {
    fun packet(mac: String): ByteArray {
        require(Regex("^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$").matches(mac))
        val address = mac.split(':').map { it.toInt(16).toByte() }.toByteArray()
        require(address.any { it != 0.toByte() } && (address[0].toInt() and 1) == 0)
        return ByteArray(102) { index ->
            if (index < 6) 0xff.toByte() else address[(index - 6) % 6]
        }
    }

    fun send(mac: String, broadcast: String) {
        require(TvProtocol.validIp(broadcast))
        val bytes = packet(mac)
        val destination = InetAddress.getByName(broadcast)
        val network = Collections.list(NetworkInterface.getNetworkInterfaces())
            .filter { it.isUp && !it.isLoopback }
            .flatMap { it.interfaceAddresses }
            .firstOrNull { it.broadcast == destination && it.address is java.net.Inet4Address }
            ?: throw IllegalArgumentException("Broadcast não corresponde à rede conectada.")
        DatagramSocket(null).use { udp ->
            udp.broadcast = true
            udp.bind(InetSocketAddress(network.address, 0))
            udp.send(DatagramPacket(bytes, bytes.size, destination, 9))
        }
    }
}
