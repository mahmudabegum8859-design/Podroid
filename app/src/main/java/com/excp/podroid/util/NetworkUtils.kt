/*
 * Podroid - Rootless Podman for Android
 * Copyright (C) 2024-2026 Podroid contributors
 *
 * Tiny shared helper for resolving the device's primary IP address (IPv4
 * preferred, global IPv6 as a last resort). Used by both PodroidService (when
 * launching QEMU) and the Settings/Home UI (to display "Phone IP: …" next to
 * port-forward rules).
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
     * Strategy (three layers so "unknown" is a last resort, not a common case):
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
     *
     * 3. If there is no usable IPv4 at all (IPv6-only cellular w/o CLAT, etc.),
     *    return a routable global IPv6 instead of "unknown".
     */
    fun localIpv4(context: Context): String {
        val cm = try {
            context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        } catch (_: Exception) {
            null
        }
        cm?.let { firstIpv4ByTransportPreference(it) }?.let { return it }
        firstUsableInterfaceIpv4()?.let { return it }
        // No IPv4 anywhere (IPv6-only cellular, VPN-only, airplane-mode
        // tethering). Return a global IPv6 rather than "unknown" — the label
        // is "Phone IP" and a routable v6 address is far more useful than
        // "unknown" to anyone trying to reach the VM/SSH.
        firstUsableInterfaceIpv6()?.let { return it }
        return "unknown"
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
        walkUpInterfaces { addr ->
            if (addr is Inet4Address &&
                !addr.isLoopbackAddress &&
                !addr.isAnyLocalAddress &&
                !addr.isLinkLocalAddress
            ) {
                addrs += addr
            }
        }
        addrs.firstOrNull { it.isSiteLocalAddress }?.hostAddress
            ?: addrs.firstOrNull()?.hostAddress
    } catch (_: Exception) {
        null
    }

    /**
     * Same scan for global IPv6 (used only when no IPv4 exists at all). Skips
     * link-local (fe80::/10, which is unscoped-routing garbage outside the
     * link) and the deprecated site-local range; whatever is left is a
     * routable global address.
     */
    private fun firstUsableInterfaceIpv6(): String? = try {
        var best: java.net.Inet6Address? = null
        walkUpInterfaces { addr ->
            if (addr is java.net.Inet6Address &&
                !addr.isLoopbackAddress &&
                !addr.isAnyLocalAddress &&
                !addr.isLinkLocalAddress &&
                !addr.isSiteLocalAddress &&
                !addr.isMulticastAddress
            ) {
                best = addr
            }
        }
        best?.hostAddress
    } catch (_: Exception) {
        null
    }

    /** Enumerates up interfaces, skipping tunnels/virtuals, invoking [visit] per address. */
    private fun walkUpInterfaces(visit: (java.net.InetAddress) -> Unit) {
        val ifaces = NetworkInterface.getNetworkInterfaces()
        while (ifaces.hasMoreElements()) {
            val ni = ifaces.nextElement()
            val name = ni.name.orEmpty()
            if (!ni.isUp || ni.isLoopback) continue
            // Tunnels/virtuals aren't LAN endpoints the user can SSH to.
            if (name.startsWith("tun") || name.startsWith("ppp") || name == "dummy0") continue
            for (addr in ni.inetAddresses) {
                visit(addr)
            }
        }
    }

    /**
     * The DNS servers the device is actually using, as IPv4 dotted-quad strings,
     * in preference order. Used to seed the guest's `resolv.conf`: hardcoding
     * public resolvers (8.8.8.8) inside the VM fails on carriers that block
     * outbound DNS to non-carrier servers, so we pass the device's own resolvers
     * through instead (same approach as StrykerApp's `bootroot`).
     *
     * Source order:
     *   1. ConnectivityManager's per-link DNS (most accurate — reflects the
     *      active transport's real servers, incl. VPN/Private DNS quirks).
     *   2. The `net.dns1..4` system properties (legacy fallback the way
     *      StrykerApp reads them via `getprop net.dnsN`).
     * Drops empty/loopback/link-local entries. Returns an empty list when no
     * usable resolver is discoverable (callers then fall back to public DNS).
     */
    fun deviceDnsServers(context: Context): List<String> {
        val out = LinkedHashSet<String>()
        val cm = try {
            context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        } catch (_: Exception) {
            null
        }
        fun add(addr: java.net.InetAddress?) {
            if (addr == null) return
            if (addr is Inet4Address &&
                !addr.isLoopbackAddress &&
                !addr.isLinkLocalAddress &&
                !addr.isAnyLocalAddress
            ) {
                out.add(addr.hostAddress)
            }
        }
        cm?.activeNetwork?.let { active ->
            runCatching { cm.getLinkProperties(active)?.dnsServers }.getOrNull()?.forEach { add(it) }
        }
        if (out.isEmpty()) {
            for (i in 1..4) {
                val p = try {
                    getSystemProperty("net.dns$i")
                } catch (_: Exception) {
                    null
                }
                if (!p.isNullOrEmpty() && p.matches(Regex("^\\d{1,3}(\\.\\d{1,3}){3}$"))) out.add(p)
            }
        }
        return out.toList()
    }

    /**
     * Reads an Android system property. `android.os.SystemProperties` is a
     * hidden class (not on the public compile classpath), so we call it via
     * reflection — the same value `getprop net.dnsN` returns on the shell.
     */
    private fun getSystemProperty(name: String): String? = try {
        val cls = Class.forName("android.os.SystemProperties")
        val m = cls.getMethod("get", String::class.java)
        m.invoke(null, name) as? String
    } catch (_: Exception) {
        null
    }
}
