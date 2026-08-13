/*
 * Podroid - Rootless Podman for Android
 * Copyright (C) 2024-2026 Podroid contributors
 *
 * Tiny shared helper for resolving the device's primary IPv4 address.
 * Used by both PodroidService (when launching QEMU) and the Settings UI
 * (to display "Phone IP: …" next to port-forward rules).
 */
package com.excp.podroid.util

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import java.net.Inet4Address
import java.net.NetworkInterface

object NetworkUtils {
    /**
     * The address users would `ssh root@<this> -p 9922` to, from another
     * device on the same LAN.
     *
     * Strategy (two layers so "unknown" is a last resort, not a common case):
     *
     * 1. ConnectivityManager, picked by transport preference rather than by
     *    address-pattern matching: WiFi first (LAN), then Ethernet (USB-C
     *    dongles), then Cellular (hotspot or LTE), skipping VPN tunnels.
     *    No address-range literals — selection is a policy on transports, so
     *    it stays correct whatever network the user is on.
     *
     * 2. If that finds nothing (IPv6-only default route, VPN-only, airplane
     *    mode + tethering, or a vendor ConnectivityManager that lies), fall
     *    back to enumerating `NetworkInterface`s directly for any usable IPv4.
     */
    fun localIpv4(context: Context): String {
        val cm = try {
            context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        } catch (_: Exception) {
            null
        }
        cm?.let { firstIpv4ByTransportPreference(it) }?.let { return it }
        return firstUsableInterfaceIpv4() ?: "unknown"
    }

    private val TRANSPORT_PREFERENCE = intArrayOf(
        NetworkCapabilities.TRANSPORT_WIFI,
        NetworkCapabilities.TRANSPORT_ETHERNET,
        NetworkCapabilities.TRANSPORT_CELLULAR,
    )

    private fun firstIpv4ByTransportPreference(cm: ConnectivityManager): String? {
        // Prefer the active (default-route) network first — it's the address
        // that traffic actually leaves through, not just any connected interface.
        cm.activeNetwork?.let { active ->
            val caps = cm.getNetworkCapabilities(active)
            if (caps != null && !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                val link = cm.getLinkProperties(active)
                if (link != null) {
                    for (la in link.linkAddresses) {
                        val addr = la.address
                        if (addr is Inet4Address && !addr.isLoopbackAddress) {
                            return addr.hostAddress
                        }
                    }
                }
            }
        }
        // Fall back to transport-preference scan for edge cases (e.g. active network
        // has only IPv6, but a secondary WiFi interface has an IPv4 address).
        for (preferred in TRANSPORT_PREFERENCE) {
            for (net in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(net) ?: continue
                if (!caps.hasTransport(preferred)) continue
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                val link = cm.getLinkProperties(net) ?: continue
                for (la in link.linkAddresses) {
                    val addr = la.address
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        return addr.hostAddress
                    }
                }
            }
        }
        return null
    }

    /**
     * Last-resort scan of raw kernel interfaces. Catches devices where the
     * ConnectivityManager reports nothing usable: IPv6-only default routes
     * (common on cellular), VPN-only connections, and vendor quirks. Skips
     * loopback, link-local (169.254.x), tunnels, and dummy interfaces. Prefers
     * a private-LAN (site-local) address — the one users actually SSH to —
     * and falls back to any other IPv4 (e.g. a CLAT 192.0.0.x on IPv6-only
     * cellular, which is real and routable).
     */
    private fun firstUsableInterfaceIpv4(): String? = try {
        val addrs = mutableListOf<Inet4Address>()
        val ifaces = NetworkInterface.getNetworkInterfaces()
        while (ifaces.hasMoreElements()) {
            val ni = ifaces.nextElement()
            val name = ni.name.orEmpty()
            if (!ni.isUp || ni.isLoopback) continue
            // Tunnels/virtuals aren't LAN endpoints the user can SSH to.
            if (name.startsWith("tun") || name.startsWith("ppp") || name == "dummy0") continue
            for (addr in ni.inetAddresses) {
                if (addr is Inet4Address &&
                    !addr.isLoopbackAddress &&
                    !addr.isAnyLocalAddress &&
                    !addr.isLinkLocalAddress
                ) {
                    addrs += addr
                }
            }
        }
        addrs.firstOrNull { it.isSiteLocalAddress }?.hostAddress
            ?: addrs.firstOrNull()?.hostAddress
    } catch (_: Exception) {
        null
    }
}
