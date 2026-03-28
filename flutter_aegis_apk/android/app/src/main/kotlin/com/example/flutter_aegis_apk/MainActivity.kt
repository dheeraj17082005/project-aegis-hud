package com.example.flutter_aegis_apk

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity(), WifiP2pManager.PeerListListener, WifiP2pManager.ConnectionInfoListener {

    private val CHANNEL = "com.aegis.mesh/nav"
    private val EVENT_CHANNEL = "com.aegis.mesh/events"
    private val PERMISSION_REQUEST_CODE = 1001
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var manager: WifiP2pManager
    private lateinit var channel: WifiP2pManager.Channel
    private lateinit var receiver: BroadcastReceiver
    private val intentFilter = IntentFilter()

    private var eventSink: EventChannel.EventSink? = null

    private val MSG_PORT = 8888
    private var udpSocket: DatagramSocket? = null
    private val isRunningUdp = AtomicBoolean(false)

    private val BEACON_PORT = 9999
    private val BEACON_INTERVAL_MS = 3000L
    private val PEER_TTL_MS = 10_000L
    private val isBeaconRunning = AtomicBoolean(false)
    private var beaconSocket: DatagramSocket? = null

    // LAN peer maps — ONLY Aegis devices that respond with AEGIS_BEACON
    private val lanPeers     = ConcurrentHashMap<String, Long>()   // peerId -> last-seen epoch
    private val lanPeerIps   = ConcurrentHashMap<String, String>() // peerId -> ip
    private val lanPeerNames = ConcurrentHashMap<String, String>() // peerId -> callsign or model

    private lateinit var deviceId: String
    private var myCallsign: String = ""

    private lateinit var bleTransport: BleTransport
    private var currentBlePeers = listOf<Map<String, Any?>>()

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        deviceId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
            ?: "aegis_${System.currentTimeMillis()}"
        android.util.Log.d("AegisNative", "Device ID: $deviceId")

        deviceId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
            ?: "aegis_${System.currentTimeMillis()}"
        android.util.Log.d("AegisNative", "Device ID: $deviceId")

        bleTransport = BleTransport.getInstance(this)
        bleTransport.initialize(
            deviceId = deviceId,
            onMsg = { message, sender ->
                mainHandler.post {
                    sendEvent(mapOf(
                        "type" to "messageReceived",
                        "message" to message,
                        "sender" to sender,
                        "transport" to "ble"
                    ))
                }
            },
            onPeers = { peers ->
                currentBlePeers = peers
                mainHandler.post { emitCombinedPeers() }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            android.util.Log.d("AegisNative", "Command: ${call.method}")
            when (call.method) {
                "startDiscovery" -> {
                    // Wi-Fi Direct discovery is kept for forming groups/connection,
                    // but peers are NOT shown until validated via LAN beacon
                    if (!::manager.isInitialized) {
                        result.error("P2P_UNINITIALIZED", "WifiP2pManager not available.", null)
                    } else {
                        startDiscovery(); result.success(true)
                    }
                }
                "stopDiscovery"     -> { stopDiscovery(); result.success(true) }
                "startLanDiscovery" -> { startBeaconBroadcast(); startBeaconListener(); result.success(true) }
                "stopLanDiscovery"  -> { stopBeacon(); result.success(true) }
                "getDeviceId" -> {
                    result.success(deviceId)
                }
                "setCallsign" -> {
                    myCallsign = call.argument<String>("callsign") ?: ""
                    android.util.Log.d("AegisNative", "Callsign set: '$myCallsign'")
                    result.success(true)
                }
                "broadcastMessage" -> {
                    broadcastMessage(call.argument<String>("message") ?: "")
                    result.success(true)
                }
                "sendMessage" -> {
                    sendPrivateToTarget(
                        call.argument<String>("targetId") ?: "",
                        call.argument<String>("message") ?: ""
                    )
                    result.success(true)
                }
                "startBle"       -> { bleTransport.start(); result.success(true) }
                "stopBle"        -> { bleTransport.stop(); result.success(true) }
                "sendBleMessage" -> {
                    bleTransport.broadcastMessage(call.argument<String>("message") ?: "")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    android.util.Log.d("AegisNative", "EventChannel attached")
                }
                override fun onCancel(arguments: Any?) { eventSink = null }
            }
        )

        initP2p()
        startUdpServer()
        
        // Initial permission check (mostly for background/hot-start)
        checkAndRequestPermissions()
    }

    private fun checkAndRequestPermissions(): Boolean {
        val permissions = mutableListOf<String>()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_SCAN)
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
            permissions.add(Manifest.permission.BLUETOOTH_ADVERTISE)
            permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
        } else {
            permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }

        val missing = permissions.filter { 
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED 
        }

        if (missing.isNotEmpty()) {
            android.util.Log.d("AegisNative", "Missing permissions: ${missing.joinToString()}")
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), PERMISSION_REQUEST_CODE)
            return false
        }
        return true
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            if (allGranted) {
                android.util.Log.d("AegisNative", "All permissions granted. Restarting radios.")
                // Restart BLE or discovery if needed
                bleTransport.start()
            } else {
                android.util.Log.e("AegisNative", "Permissions denied. BLE & LAN features may be disabled.")
                sendEvent(mapOf("type" to "error", "message" to "Permissions denied. Peer discovery impossible."))
            }
        }
    }

    // ── Wi-Fi Direct (transport layer only, NOT for peer listing) ────────────

    private fun initP2p() {
        try {
            manager = getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
            channel = manager.initialize(this, Looper.getMainLooper(), null)
            intentFilter.addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            intentFilter.addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            intentFilter.addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            intentFilter.addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
            receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    when (intent.action) {
                        WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION ->
                            manager.requestPeers(channel, this@MainActivity)
                        WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                            val info = intent.getParcelableExtra<android.net.NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
                            if (info?.isConnected == true) manager.requestConnectionInfo(channel, this@MainActivity)
                        }
                    }
                }
            }
            registerReceiver(receiver, intentFilter)
        } catch (e: Exception) {
            android.util.Log.e("AegisNative", "P2P init failed: ${e.message}")
        }
    }

    private fun startDiscovery() {
        manager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = sendEvent(mapOf("type" to "discoveryState", "state" to "started"))
            override fun onFailure(r: Int) = sendEvent(mapOf("type" to "error", "message" to "P2P failed: $r"))
        })
    }

    private fun stopDiscovery() {
        manager.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = sendEvent(mapOf("type" to "discoveryState", "state" to "stopped"))
            override fun onFailure(r: Int) {}
        })
    }

    /**
     * Wi-Fi Direct peers callback — we log them but DO NOT add to the UI peer list.
     * Only devices running Aegis (validated via LAN beacon) appear in the tunnel list.
     * Wi-Fi Direct is used purely as a transport mechanism for offline mesh groups.
     */
    override fun onPeersAvailable(peerList: WifiP2pDeviceList) {
        android.util.Log.d("AegisNative", "Wi-Fi Direct scan found ${peerList.deviceList.size} raw devices (NOT shown in UI)")
    }

    override fun onConnectionInfoAvailable(info: android.net.wifi.p2p.WifiP2pInfo) {
        if (info.groupFormed && info.groupOwnerAddress != null && !info.isGroupOwner) {
            val goIp = info.groupOwnerAddress.hostAddress ?: return
            lanPeerIps["GO_OFFLINE"] = goIp
            CoroutineScope(Dispatchers.Main).launch {
                sendEvent(mapOf("type" to "discoveryState", "state" to "offline_mesh_formed"))
            }
        }
    }

    // ── LAN Beacon (the ONLY source of visible peers) ───────────────────────

    private fun startBeaconBroadcast() {
        if (isBeaconRunning.get()) return
        isBeaconRunning.set(true)

        // Beacon TX: constantly broadcast our identity
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val socket = DatagramSocket().also { it.broadcast = true }
                while (isBeaconRunning.get()) {
                    val payload = "AEGIS_BEACON|$deviceId|${Build.MODEL}|$myCallsign".toByteArray()
                    runCatching {
                        socket.send(DatagramPacket(payload, payload.size, InetAddress.getByName("255.255.255.255"), BEACON_PORT))
                    }
                    runCatching {
                        val sub = getSubnetBroadcastAddress()
                        if (sub != null) socket.send(DatagramPacket(payload, payload.size, InetAddress.getByName(sub), BEACON_PORT))
                    }
                    delay(BEACON_INTERVAL_MS)
                }
                socket.close()
            } catch (e: Exception) {
                android.util.Log.e("AegisNative", "Beacon TX error: ${e.message}")
            }
        }

        // Stale peer sweep: remove peers we haven't heard from in PEER_TTL_MS
        CoroutineScope(Dispatchers.IO).launch {
            while (isBeaconRunning.get()) {
                delay(5_000L)
                val now = System.currentTimeMillis()
                val stale = lanPeers.filter { now - it.value > PEER_TTL_MS }.keys
                if (stale.isNotEmpty()) {
                    stale.forEach { lanPeers.remove(it); lanPeerIps.remove(it); lanPeerNames.remove(it) }
                    CoroutineScope(Dispatchers.Main).launch { emitCombinedPeers() }
                }
            }
        }
    }

    private fun startBeaconListener() {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                beaconSocket = DatagramSocket(null).also { it.reuseAddress = true; it.bind(InetSocketAddress(BEACON_PORT)) }
                val buffer = ByteArray(512)
                while (isBeaconRunning.get()) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    beaconSocket?.receive(packet)
                    val data = String(packet.data, 0, packet.length)
                    if (!data.startsWith("AEGIS_BEACON|")) continue

                    val parts = data.split("|")
                    val peerId       = parts.getOrNull(1) ?: "unknown"
                    val peerModel    = parts.getOrNull(2) ?: "Unknown"
                    val peerCallsign = parts.getOrNull(3)?.trim() ?: ""
                    val ip           = packet.address.hostAddress ?: continue

                    if (peerId == deviceId) continue  // own beacon echo

                    val isNew = !lanPeers.containsKey(peerId)
                    lanPeers[peerId]     = System.currentTimeMillis()
                    lanPeerIps[peerId]   = ip
                    lanPeerNames[peerId] = if (peerCallsign.isNotEmpty()) peerCallsign else peerModel

                    if (isNew) {
                        android.util.Log.d("AegisNative", "NEW Aegis peer: $peerId  name='${lanPeerNames[peerId]}'  ip=$ip")
                        CoroutineScope(Dispatchers.Main).launch { emitCombinedPeers() }
                    }
                }
            } catch (e: Exception) {
                if (isBeaconRunning.get()) android.util.Log.e("AegisNative", "Beacon RX error: ${e.message}")
            }
        }
    }

    private fun stopBeacon() {
        isBeaconRunning.set(false)
        beaconSocket?.close()
        lanPeers.clear(); lanPeerIps.clear(); lanPeerNames.clear()
    }

    // ── Peer Aggregation (ONLY verified Aegis peers) ────────────────────────

    private fun emitCombinedPeers() {
        val combined = mutableListOf<Map<String, Any?>>()

        // 1. LAN beacon peers — these are VERIFIED Aegis devices
        for ((peerId, _) in lanPeers) {
            val name = lanPeerNames[peerId] ?: "Ghost_${peerId.takeLast(4)}"
            combined.add(mapOf("peerId" to peerId, "deviceName" to name, "source" to "lan"))
        }

        // 2. BLE GATT peers — these advertise our Aegis UUID, so they're verified too
        for (ble in currentBlePeers) {
            if (combined.none { it["peerId"] == ble["peerId"] }) {
                combined.add(ble)
            }
        }

        // NOTE: Wi-Fi Direct raw scan peers are intentionally NOT included.
        // Random TVs, printers, and non-Aegis phones would pollute the list.

        android.util.Log.d("AegisNative", "Verified Aegis peers: ${combined.size}  (LAN=${lanPeers.size}, BLE=${currentBlePeers.size})")
        sendEvent(mapOf("type" to "peersFound", "peers" to combined))
    }

    // ── Messaging ───────────────────────────────────────────────────────────

    private fun startUdpServer() {
        isRunningUdp.set(true)
        CoroutineScope(Dispatchers.IO).launch {
            try {
                udpSocket = DatagramSocket(null).also { it.reuseAddress = true; it.bind(InetSocketAddress(MSG_PORT)) }
                val buffer = ByteArray(8192)
                while (isRunningUdp.get()) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    udpSocket?.receive(packet)
                    val received = String(packet.data, 0, packet.length)
                    val senderIp = packet.address.hostAddress ?: ""
                    android.util.Log.d("AegisNative", "UDP in from $senderIp: ${received.take(100)}")
                    CoroutineScope(Dispatchers.Main).launch {
                        sendEvent(mapOf("type" to "messageReceived", "message" to received, "sender" to senderIp))
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("AegisNative", "UDP server error: ${e.message}")
            }
        }
    }

    /** Public broadcast — send to everyone. */
    private fun broadcastMessage(message: String) {
        CoroutineScope(Dispatchers.IO).launch {
            val data = message.toByteArray()
            // Broadcast methods
            runCatching {
                DatagramSocket().use { s ->
                    s.broadcast = true
                    s.send(DatagramPacket(data, data.size, InetAddress.getByName("255.255.255.255"), MSG_PORT))
                }
            }
            runCatching {
                val sub = getSubnetBroadcastAddress()
                if (sub != null) DatagramSocket().use { s ->
                    s.broadcast = true
                    s.send(DatagramPacket(data, data.size, InetAddress.getByName(sub), MSG_PORT))
                }
            }
            // Direct unicast to every known Aegis peer for reliability
            for ((_, ip) in lanPeerIps) {
                runCatching {
                    DatagramSocket().use { s ->
                        s.send(DatagramPacket(data, data.size, InetAddress.getByName(ip), MSG_PORT))
                    }
                }
            }
        }
    }

    /**
     * Private message — targeted delivery ONLY. No broadcast.
     * Sends directly to the target's known IP address.
     */
    private fun sendPrivateToTarget(targetId: String, message: String) {
        CoroutineScope(Dispatchers.IO).launch {
            val data = message.toByteArray()
            val ip = lanPeerIps[targetId]

            if (!ip.isNullOrEmpty()) {
                runCatching {
                    DatagramSocket().use { s ->
                        s.send(DatagramPacket(data, data.size, InetAddress.getByName(ip), MSG_PORT))
                    }
                    android.util.Log.d("AegisNative", "Private → $targetId at $ip  ✓")
                }.onFailure {
                    android.util.Log.e("AegisNative", "Private → $targetId FAILED: ${it.message}")
                }
            } else {
                android.util.Log.e("AegisNative", "Private → $targetId: No IP found. Cannot deliver.")
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun getSubnetBroadcastAddress(): String? {
        return try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return null
            val dhcp = wm.dhcpInfo ?: return null
            val b = (dhcp.ipAddress and dhcp.netmask) or dhcp.netmask.inv()
            "${b and 0xFF}.${b shr 8 and 0xFF}.${b shr 16 and 0xFF}.${b shr 24 and 0xFF}"
        } catch (_: Exception) { null }
    }

    private fun sendEvent(event: Map<String, Any?>) {
        eventSink?.success(event) ?: android.util.Log.w("AegisNative", "eventSink null, dropped: ${event["type"]}")
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(receiver) } catch (_: Exception) {}
        isRunningUdp.set(false); udpSocket?.close()
        stopBeacon()
        if (::bleTransport.isInitialized) bleTransport.stop()
    }
}
