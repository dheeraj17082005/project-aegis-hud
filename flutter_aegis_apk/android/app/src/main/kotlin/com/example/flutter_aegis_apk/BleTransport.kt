package com.example.flutter_aegis_apk

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import androidx.core.content.ContextCompat
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.*

/**
 * Robust BLE transport for Aegis mesh.
 * Guarantees a single instance, explicit state handling, and detailed logs for debugging.
 */
class BleTransport private constructor(private val context: Context) {

    companion object {
        private const val TAG = "AegisBLE"
        private val SERVICE_UUID = UUID.fromString("0000ae81-0000-1000-8000-00805f9b34fb")
        private val CHAR_UUID_MSG = UUID.fromString("0000ae82-0000-1000-8000-00805f9b34fb")
        private const val PEER_TTL_MS = 30_000L
        private const val HEARTBEAT_INTERVAL_MS = 5_000L
        private const val SCAN_DELAY_MS = 1_000L

        @Volatile
        private var instance: BleTransport? = null

        fun getInstance(context: Context): BleTransport {
            return instance ?: synchronized(this) {
                instance ?: BleTransport(context.applicationContext).also { instance = it }
            }
        }
    }

    // ---------- State ----------
    private enum class State { IDLE, ADVERTISING, SCANNING, CONNECTED, ERROR }
    private val currentState = AtomicReference(State.IDLE)
    private var isRunning = false

    // ---------- Handlers & Coroutines ----------
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // ---------- Callbacks to Flutter ----------
    private var deviceId: String = "Unknown"
    private var onMessageReceived: ((String, String) -> Unit)? = null
    private var onPeersUpdated: ((List<Map<String, Any?>>) -> Unit)? = null

    // ---------- BLE internals ----------
    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val bluetoothAdapter = bluetoothManager?.adapter
    private var gattServer: BluetoothGattServer? = null
    private val activeClients = ConcurrentHashMap<String, BluetoothGatt>()
    private val pendingChunks = ConcurrentHashMap<String, LinkedBlockingQueue<ByteArray>>()
    private val isWriting = ConcurrentHashMap<String, Boolean>()
    private val discoveredPeers = ConcurrentHashMap<String, String>()
    private val peerLastSeen = ConcurrentHashMap<String, Long>()
    private val rxBuffers = ConcurrentHashMap<String, StringBuilder>()

    // ---------- Public API ----------
    fun initialize(id: String, onMsg: (String, String) -> Unit, onPeers: (List<Map<String, Any?>>) -> Unit) {
        deviceId = id
        onMessageReceived = onMsg
        onPeersUpdated = onPeers
    }

    @SuppressLint("MissingPermission")
    fun start() {
        if (!hasPermissions()) {
            Log.e(TAG, "Missing required BLE permissions – aborting start.")
            return
        }
        if (bluetoothAdapter?.isEnabled != true) {
            Log.e(TAG, "Bluetooth is disabled – aborting start.")
            return
        }
        if (isRunning) return
        isRunning = true
        Log.i(TAG, "BLE transport starting – initializing GATT server.")
        try {
            setupGattServer()
            // Radio will start once onServiceAdded succeeds.
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start BLE transport: ${e.message}")
            updateState(State.ERROR)
        }
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        if (!isRunning) return
        isRunning = false
        updateState(State.IDLE)
        Log.i(TAG, "Stopping BLE transport and releasing resources.")
        bluetoothAdapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        bluetoothAdapter?.bluetoothLeScanner?.stopScan(scanCallback)
        activeClients.values.forEach { it.disconnect(); it.close() }
        activeClients.clear()
        gattServer?.close()
        gattServer = null
        discoveredPeers.clear()
        peerLastSeen.clear()
        rxBuffers.clear()
        pendingChunks.clear()
        isWriting.clear()
        emitPeers()
    }

    @SuppressLint("MissingPermission")
    fun broadcastMessage(message: String) {
        val payload = "$message\u0000"
        val bytes = payload.toByteArray(Charsets.UTF_8)
        val chunks = bytes.toList().chunked(180) { it.toByteArray() }
        activeClients.values.forEach { gatt ->
            val address = gatt.device.address
            val queue = pendingChunks.computeIfAbsent(address) { LinkedBlockingQueue() }
            queue.addAll(chunks)
            sendNextChunk(gatt)
        }
    }

    // ---------- Internal Helpers ----------
    private fun updateState(newState: State) {
        currentState.set(newState)
        Log.i(TAG, "BLE State → $newState")
    }

    @SuppressLint("MissingPermission")
    private fun setupGattServer() {
        gattServer = bluetoothManager?.openGattServer(context, gattServerCallback)
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val charMsg = BluetoothGattCharacteristic(
            CHAR_UUID_MSG,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        service.addCharacteristic(charMsg)
        Log.d(TAG, "Adding Aegis GATT service to server.")
        gattServer?.addService(service)
    }

    @SuppressLint("MissingPermission")
    private fun startRadioOperations() {
        updateState(State.ADVERTISING)
        // ---- Advertising ----
        val advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        val advSettings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .build()
        val advData = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .setIncludeDeviceName(false)
            .build()
        advertiser?.startAdvertising(advSettings, advData, advertiseCallback)
        Log.i(TAG, "Advertising started.")

        // ---- Scanning (staggered) ----
        mainHandler.postDelayed({
            if (!isRunning) return@postDelayed
            val scanner = bluetoothAdapter?.bluetoothLeScanner
            val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build()
            val scanSettings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            scanner?.startScan(listOf(filter), scanSettings, scanCallback)
            updateState(State.SCANNING)
            Log.i(TAG, "Scanning started after $SCANN_DELAY_MS ms delay.")
        }, SCAN_DELAY_MS)

        // ---- Heartbeat & TTL sweep ----
        startHeartbeat()
        startTtlSweep()
    }

    @SuppressLint("MissingPermission")
    private fun sendNextChunk(gatt: BluetoothGatt) {
        val address = gatt.device.address
        if (isWriting[address] == true) return
        val queue = pendingChunks[address] ?: return
        val chunk = queue.peek() ?: return
        val service = gatt.getService(SERVICE_UUID) ?: return
        val characteristic = service.getCharacteristic(CHAR_UUID_MSG) ?: return
        isWriting[address] = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(characteristic, chunk, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
        } else {
            @Suppress("DEPRECATION")
            characteristic.value = chunk
            gatt.writeCharacteristic(characteristic)
        }
    }

    // ---------- Callbacks ----------
    private val gattClientCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            val address = gatt.device.address
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                Log.i(TAG, "Connected to $address – setting priority & MTU.")
                gatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
                gatt.requestMtu(247)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Log.w(TAG, "Disconnected from $address – cleaning up.")
                activeClients.remove(address)
                discoveredPeers.remove(address)
                gatt.close()
                emitPeers()
            }
        }

        @SuppressLint("MissingPermission")
        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.i(TAG, "MTU $mtu negotiated for ${gatt.device.address}, discovering services.")
                gatt.discoverServices()
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                val address = gatt.device.address
                peerLastSeen[address] = System.currentTimeMillis()
                discoveredPeers[address] = "Ghost_${address.takeLast(4).replace(":", "")}" // simple display name
                emitPeers()
                Log.i(TAG, "Services discovered for $address – peer added.")
            }
        }

        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            val address = gatt.device.address
            isWriting[address] = false
            if (status == BluetoothGatt.GATT_SUCCESS) {
                pendingChunks[address]?.poll()
                sendNextChunk(gatt)
            } else {
                Log.e(TAG, "Write failed for $address with status $status – dropping pending data.")
                pendingChunks[address]?.clear()
            }
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.i(TAG, "GATT service added – starting radio operations.")
                startRadioOperations()
            } else {
                Log.e(TAG, "Failed to add GATT service, status $status.")
                updateState(State.ERROR)
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            if (characteristic.uuid != CHAR_UUID_MSG || value == null) return
            val address = device.address
            val buffer = rxBuffers.computeIfAbsent(address) { StringBuilder() }
            peerLastSeen[address] = System.currentTimeMillis()
            val chunk = String(value, Charsets.UTF_8)
            if (chunk.endsWith("\u0000")) {
                buffer.append(chunk.dropLast(1))
                val fullMsg = buffer.toString()
                mainHandler.post { onMessageReceived?.invoke(fullMsg, address) }
                buffer.clear()
            } else {
                buffer.append(chunk)
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            Log.i(TAG, "Advertising successfully started.")
        }
        override fun onStartFailure(errorCode: Int) {
            Log.e(TAG, "Advertising failed with error $errorCode.")
            updateState(State.ERROR)
        }
    }

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val address = result.device.address
            if (!activeClients.containsKey(address)) {
                val gatt = result.device.connectGatt(context, false, gattClientCallback)
                activeClients[address] = gatt
                Log.i(TAG, "Discovered and connecting to $address.")
            }
        }
        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "Scanning failed with error $errorCode.")
            updateState(State.ERROR)
        }
    }

    private fun emitPeers() {
        val list = discoveredPeers.map { (mac, name) ->
            mapOf("peerId" to mac, "deviceName" to name, "source" to "ble")
        }
        mainHandler.post { onPeersUpdated?.invoke(list) }
    }

    private fun startHeartbeat() {
        scope.launch {
            while (isRunning) {
                delay(HEARTBEAT_INTERVAL_MS)
                if (activeClients.isNotEmpty()) {
                    broadcastMessage("{\"type\":\"PING\",\"sender\":\"$deviceId\"}")
                }
            }
        }
    }

    private fun startTtlSweep() {
        scope.launch {
            while (isRunning) {
                delay(15_000L)
                val now = System.currentTimeMillis()
                val stale = peerLastSeen.filter { now - it.value > PEER_TTL_MS }.keys
                stale.forEach { addr ->
                    discoveredPeers.remove(addr)
                    activeClients.remove(addr)?.close()
                    Log.i(TAG, "Peer $addr timed out – removed.")
                }
                if (stale.isNotEmpty()) emitPeers()
            }
        }
    }

    private fun hasPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val connect = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
            val scan = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
            val advertise = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED
            connect && scan && advertise
        } else {
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
    }
}
