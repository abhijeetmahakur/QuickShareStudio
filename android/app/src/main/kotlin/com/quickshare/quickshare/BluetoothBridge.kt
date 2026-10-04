package com.quickshare.quickshare

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.NetworkInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.SecureRandom
import java.util.ArrayDeque
import java.util.UUID

/**
 * Thin Android transport for QuickShare's Bluetooth path. Dart owns the protocol (chunking,
 * X25519 key agreement, encryption); this class only moves bytes:
 *
 *  - BLE advertising (QuickShare service UUID + short session id + device name) and scanning
 *  - one GATT characteristic: the central writes, the peripheral notifies
 *  - Wi-Fi Direct: the receiver creates a group, the sender joins it with the credentials it
 *    received (encrypted) over BLE; the transfer itself then runs over a TCP socket from Dart.
 *
 * Runtime permissions are requested by Dart before any of these calls.
 */
@SuppressLint("MissingPermission")
class BluetoothBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("6d2a4f1e-9c3b-4b7a-8e15-2f0c5a9b7d31")
        val CHAR_UUID: UUID = UUID.fromString("6d2a4f1e-9c3b-4b7a-8e15-2f0c5a9b7d32")
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        const val MANUFACTURER_ID = 0xFFFF
        const val REQUEST_ENABLE_BT = 4711
    }

    private val main = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "quickshare/bluetooth")
    private val events = EventChannel(messenger, "quickshare/bluetooth/events")
    private var sink: EventChannel.EventSink? = null
    var activity: Activity? = null
    private var pendingEnable: MethodChannel.Result? = null

    private val manager get() = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?
    private val adapter: BluetoothAdapter? get() = manager?.adapter

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun emit(event: Map<String, Any?>) = main.post { sink?.success(event) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "capabilities" -> result.success(capabilities())
                "requestEnable" -> requestEnable(result)
                "startScan" -> { startScan(); result.success(null) }
                "stopScan" -> { stopScan(); result.success(null) }
                "startAdvertising" -> startAdvertising(call.argument<String>("name") ?: "QuickShare",
                    call.argument<ByteArray>("session") ?: ByteArray(4), result)
                "stopAdvertising" -> { stopAdvertising(); result.success(null) }
                "notify" -> notifyCentral(call.argument<String>("address")!!, call.argument<ByteArray>("value")!!, result)
                "connectGatt" -> { connectGatt(call.argument<String>("address")!!); result.success(null) }
                "write" -> write(call.argument<ByteArray>("value")!!, result)
                "disconnectGatt" -> { disconnectGatt(); result.success(null) }
                "createGroup" -> createGroup(result)
                "connectGroup" -> connectGroup(call.argument<String>("ssid")!!, call.argument<String>("passphrase")!!, result)
                "removeGroup" -> { removeGroup(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        } catch (e: Exception) {
            result.error("failed", e.message, null)
        }
    }

    // ---------------------------------------------------------------------------------------
    // Capabilities & enabling
    // ---------------------------------------------------------------------------------------

    private fun capabilities(): Map<String, Any?> {
        val pm = context.packageManager
        val a = adapter
        return mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "ble" to pm.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE),
            "wifiDirect" to pm.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT),
            "advertise" to (a?.isMultipleAdvertisementSupported ?: false),
            "enabled" to (a?.isEnabled ?: false),
        )
    }

    private fun requestEnable(result: MethodChannel.Result) {
        val a = adapter ?: return result.success(false)
        if (a.isEnabled) return result.success(true)
        val act = activity ?: return result.success(false)
        pendingEnable = result
        act.startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQUEST_ENABLE_BT)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_ENABLE_BT) return false
        pendingEnable?.success(resultCode == Activity.RESULT_OK)
        pendingEnable = null
        return true
    }

    // ---------------------------------------------------------------------------------------
    // Scanning (sender)
    // ---------------------------------------------------------------------------------------

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val data = result.scanRecord?.getManufacturerSpecificData(MANUFACTURER_ID) ?: return
            if (data.size < 4) return
            val session = data.copyOfRange(0, 4)
            val name = String(data.copyOfRange(4, data.size), Charsets.UTF_8)
            emit(mapOf(
                "type" to "scan",
                "address" to result.device.address,
                "name" to name,
                "rssi" to result.rssi,
                "session" to session,
            ))
        }

        override fun onScanFailed(errorCode: Int) {
            emit(mapOf("type" to "scanFailed", "code" to errorCode))
        }
    }

    private fun startScan() {
        val scanner = adapter?.bluetoothLeScanner ?: throw IllegalStateException("Bluetooth is off")
        val filters = listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build())
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scanner.startScan(filters, settings, scanCallback)
    }

    private fun stopScan() {
        try {
            adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (_: Exception) {
        }
    }

    // ---------------------------------------------------------------------------------------
    // Advertising + GATT server (receiver)
    // ---------------------------------------------------------------------------------------

    private var gattServer: BluetoothGattServer? = null
    private var serverChar: BluetoothGattCharacteristic? = null
    /** Notifications go out one at a time; each call resolves once the stack sent it. */
    private val notifyQueue = ArrayDeque<Triple<BluetoothDevice, ByteArray, MethodChannel.Result>>()
    private var notifyInFlight: MethodChannel.Result? = null

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) {
            emit(mapOf("type" to "advertiseFailed", "code" to errorCode))
        }
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                emit(mapOf("type" to "centralConnected", "address" to device.address))
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                emit(mapOf("type" to "centralDisconnected", "address" to device.address))
            }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            emit(mapOf("type" to "centralMtu", "address" to device.address, "mtu" to mtu))
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?,
        ) {
            if (responseNeeded) gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            if (value != null) emit(mapOf("type" to "centralWrite", "address" to device.address, "value" to value))
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?,
        ) {
            if (responseNeeded) gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            if (descriptor.uuid == CCCD_UUID) emit(mapOf("type" to "centralSubscribed", "address" to device.address))
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            main.post {
                notifyInFlight?.success(status == BluetoothGatt.GATT_SUCCESS)
                notifyInFlight = null
                drainNotify()
            }
        }
    }

    private fun startAdvertising(name: String, session: ByteArray, result: MethodChannel.Result) {
        val a = adapter ?: return result.error("unavailable", "Bluetooth is not available", null)
        if (!a.isEnabled) return result.error("off", "Bluetooth is off", null)
        val advertiser = a.bluetoothLeAdvertiser ?: return result.error("unsupported", "This device cannot advertise over BLE", null)
        stopAdvertising()

        val server = manager!!.openGattServer(context, serverCallback)
        val characteristic = BluetoothGattCharacteristic(
            CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_WRITE,
        )
        characteristic.addDescriptor(BluetoothGattDescriptor(
            CCCD_UUID, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE))
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(characteristic)
        server.addService(service)
        gattServer = server
        serverChar = characteristic

        // Advertisement: the service UUID. Scan response: session id + (truncated) name.
        val nameBytes = name.toByteArray(Charsets.UTF_8).let { if (it.size > 20) it.copyOfRange(0, 20) else it }
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .setTimeout(0)
            .build()
        val data = AdvertiseData.Builder().addServiceUuid(ParcelUuid(SERVICE_UUID)).setIncludeDeviceName(false).build()
        val response = AdvertiseData.Builder().setIncludeDeviceName(false)
            .addManufacturerData(MANUFACTURER_ID, session.copyOfRange(0, 4) + nameBytes).build()
        advertiser.startAdvertising(settings, data, response, advertiseCallback)
        result.success(null)
    }

    private fun stopAdvertising() {
        try {
            adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        } catch (_: Exception) {
        }
        try {
            gattServer?.close()
        } catch (_: Exception) {
        }
        gattServer = null
        serverChar = null
        notifyQueue.forEach { it.third.success(false) }
        notifyQueue.clear()
        notifyInFlight?.success(false)
        notifyInFlight = null
    }

    private fun notifyCentral(address: String, value: ByteArray, result: MethodChannel.Result) {
        val device = adapter?.getRemoteDevice(address) ?: return result.error("unavailable", "no adapter", null)
        notifyQueue.add(Triple(device, value, result))
        drainNotify()
    }

    private fun drainNotify() {
        if (notifyInFlight != null) return
        val (device, value, result) = notifyQueue.pollFirst() ?: return
        val server = gattServer
        val characteristic = serverChar
        if (server == null || characteristic == null) {
            result.success(false)
            return
        }
        notifyInFlight = result
        val ok = if (Build.VERSION.SDK_INT >= 33) {
            server.notifyCharacteristicChanged(device, characteristic, false, value) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            characteristic.value = value
            @Suppress("DEPRECATION")
            server.notifyCharacteristicChanged(device, characteristic, false)
        }
        if (!ok) {
            notifyInFlight = null
            result.success(false)
            drainNotify()
        }
    }

    // ---------------------------------------------------------------------------------------
    // GATT client (sender)
    // ---------------------------------------------------------------------------------------

    private var gatt: BluetoothGatt? = null
    private var clientChar: BluetoothGattCharacteristic? = null
    private var mtu = 23
    private var pendingWrite: MethodChannel.Result? = null

    private val clientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                main.post { g.requestMtu(247) }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                emit(mapOf("type" to "peripheralDisconnected", "status" to status))
                g.close()
                if (gatt == g) gatt = null
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, newMtu: Int, status: Int) {
            mtu = if (status == BluetoothGatt.GATT_SUCCESS) newMtu else 23
            main.post { g.discoverServices() }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            val characteristic = g.getService(SERVICE_UUID)?.getCharacteristic(CHAR_UUID)
            if (characteristic == null) {
                emit(mapOf("type" to "peripheralError", "message" to "Not a QuickShare device"))
                return
            }
            clientChar = characteristic
            g.setCharacteristicNotification(characteristic, true)
            val cccd = characteristic.getDescriptor(CCCD_UUID)
            if (Build.VERSION.SDK_INT >= 33) {
                g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
            } else {
                @Suppress("DEPRECATION")
                cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                @Suppress("DEPRECATION")
                g.writeDescriptor(cccd)
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            emit(mapOf("type" to "peripheralReady", "mtu" to mtu))
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            pendingWrite?.success(status == BluetoothGatt.GATT_SUCCESS)
            pendingWrite = null
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            emit(mapOf("type" to "peripheralNotify", "value" to value))
        }

        @Deprecated("Pre-API 33 callback")
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < 33) {
                @Suppress("DEPRECATION")
                emit(mapOf("type" to "peripheralNotify", "value" to characteristic.value))
            }
        }
    }

    private fun connectGatt(address: String) {
        disconnectGatt()
        val device = adapter?.getRemoteDevice(address) ?: throw IllegalStateException("Bluetooth is off")
        gatt = device.connectGatt(context, false, clientCallback, BluetoothDevice.TRANSPORT_LE)
    }

    private fun write(value: ByteArray, result: MethodChannel.Result) {
        val g = gatt ?: return result.error("disconnected", "Not connected", null)
        val characteristic = clientChar ?: return result.error("disconnected", "Not ready", null)
        pendingWrite = result
        val started = if (Build.VERSION.SDK_INT >= 33) {
            g.writeCharacteristic(characteristic, value, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            characteristic.value = value
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            @Suppress("DEPRECATION")
            g.writeCharacteristic(characteristic)
        }
        if (!started) {
            pendingWrite = null
            result.success(false)
        }
    }

    private fun disconnectGatt() {
        try {
            gatt?.disconnect()
            gatt?.close()
        } catch (_: Exception) {
        }
        gatt = null
        clientChar = null
    }

    // ---------------------------------------------------------------------------------------
    // Wi-Fi Direct
    // ---------------------------------------------------------------------------------------

    private val p2p by lazy { context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager? }
    private val p2pChannel by lazy { p2p?.initialize(context, Looper.getMainLooper(), null) }

    private fun randomText(length: Int): String {
        val alphabet = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        val rnd = SecureRandom()
        return (1..length).map { alphabet[rnd.nextInt(alphabet.length)] }.joinToString("")
    }

    private fun createGroup(result: MethodChannel.Result) {
        val manager = p2p ?: return result.error("unsupported", "Wi-Fi Direct is not available", null)
        val channel = p2pChannel ?: return result.error("unsupported", "Wi-Fi Direct is not available", null)
        if (Build.VERSION.SDK_INT < 29) return result.error("unsupported", "Needs Android 10 or newer", null)
        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = create()
            override fun onFailure(reason: Int) = create()

            fun create() {
                val config = WifiP2pConfig.Builder()
                    .setNetworkName("DIRECT-qs-" + randomText(6))
                    .setPassphrase(randomText(16))
                    .enablePersistentMode(false)
                    .build()
                manager.createGroup(channel, config, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        // Group info is available a moment later.
                        main.postDelayed({ reportGroup(manager, channel, result, 10) }, 300)
                    }

                    override fun onFailure(reason: Int) = result.error("group", "Could not create a Wi-Fi Direct group ($reason)", null)
                })
            }
        })
    }

    private fun reportGroup(manager: WifiP2pManager, channel: WifiP2pManager.Channel, result: MethodChannel.Result, retries: Int) {
        manager.requestGroupInfo(channel) { group ->
            manager.requestConnectionInfo(channel) { info ->
                val ip = info?.groupOwnerAddress?.hostAddress ?: "192.168.49.1"
                if (group != null && group.passphrase != null) {
                    result.success(mapOf("ssid" to group.networkName, "passphrase" to group.passphrase, "ip" to ip))
                } else if (retries > 0) {
                    main.postDelayed({ reportGroup(manager, channel, result, retries - 1) }, 300)
                } else {
                    result.error("group", "The Wi-Fi Direct group did not start", null)
                }
            }
        }
    }

    private var connectReceiver: BroadcastReceiver? = null

    private fun connectGroup(ssid: String, passphrase: String, result: MethodChannel.Result) {
        val manager = p2p ?: return result.error("unsupported", "Wi-Fi Direct is not available", null)
        val channel = p2pChannel ?: return result.error("unsupported", "Wi-Fi Direct is not available", null)
        if (Build.VERSION.SDK_INT < 29) return result.error("unsupported", "Needs Android 10 or newer", null)
        var answered = false
        fun answer(block: () -> Unit) {
            if (answered) return
            answered = true
            connectReceiver?.let { try { context.unregisterReceiver(it) } catch (_: Exception) {} }
            connectReceiver = null
            block()
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                @Suppress("DEPRECATION")
                val network = intent.getParcelableExtra<NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
                if (network?.isConnected != true) return
                manager.requestConnectionInfo(channel) { info ->
                    if (info != null && info.groupFormed && !info.isGroupOwner) {
                        val ip = info.groupOwnerAddress?.hostAddress ?: "192.168.49.1"
                        answer { result.success(mapOf("ip" to ip)) }
                    }
                }
            }
        }
        connectReceiver = receiver
        val filter = IntentFilter(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
        val config = WifiP2pConfig.Builder().setNetworkName(ssid).setPassphrase(passphrase).enablePersistentMode(false).build()
        manager.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {}
            override fun onFailure(reason: Int) = answer { result.error("connect", "Could not join the Wi-Fi Direct group ($reason)", null) }
        })
        main.postDelayed({ answer { result.error("timeout", "Joining the Wi-Fi Direct group timed out", null) } }, 30_000)
    }

    private fun removeGroup() {
        val manager = p2p ?: return
        val channel = p2pChannel ?: return
        manager.removeGroup(channel, null)
    }

    fun dispose() {
        stopScan()
        stopAdvertising()
        disconnectGatt()
        removeGroup()
    }
}
