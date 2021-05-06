import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_ble_connection/widgets.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.amber,
        ).copyWith(),
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  FlutterBlue _flutterBlue = FlutterBlue.instance;
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  /// Scanning
  StreamSubscription? _scanSubscription;
  Map<DeviceIdentifier, ScanResult> scanResults = Map();
  bool isScanning = false;

  /// State
  StreamSubscription? _stateSubscription;
  BluetoothState state = BluetoothState.unknown;

  /// Device
  BluetoothDevice? _device;

  bool get isConnected => (_device != null);
  StreamSubscription? deviceConnection;
  StreamSubscription? deviceStateSubscription;
  List<BluetoothService>? _services = [];
  Map<Guid, StreamSubscription> valueChangedSubscriptions = {};
  BluetoothDeviceState? deviceState = BluetoothDeviceState.disconnected;

  static const String CHARACTERISTIC_UUID = '';
  static const String kMYDEVICE = 'myDevice';
  String? _myDeviceId;
  String _temperature = '?';
  String _humidity = '?';


  @override
  void initState() {
    super.initState();
    // Subscribe to state changes
    _stateSubscription = _flutterBlue.state.listen((s) {
      setState(() {
        state = s;
      });

      _loadMyDeviceId();
    });
  }

  _loadMyDeviceId() async {
    SharedPreferences prefs = await _prefs;
    _myDeviceId = prefs.getString(kMYDEVICE) ?? '';
    print('myDeviceId: $_myDeviceId');
    if(_myDeviceId?.isNotEmpty == true) {
      _startScan();
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _scanSubscription?.cancel();
    _scanSubscription = null;
    deviceConnection?.cancel();
    deviceConnection = null;
    super.dispose();
  }

  _startScan() {
    _scanSubscription = _flutterBlue.scan(
      timeout: const Duration(seconds: 5),
      /*withServices: [
        Guid(''),
      ],*/
    ).listen(
      (scanResult) {
        /*print('localName: ${scanResult.advertisementData.localName}');
        print('manufacturerData: ${scanResult.advertisementData.manufacturerData}');
        print('serviceData: ${scanResult.advertisementData.toString()}');
        print('device: ${scanResult.device.toString()}');*/

        if(_myDeviceId == scanResult.device.id.toString()) {
          _stopScan();
          _connect(scanResult.device);
        }

        setState(() {
          scanResults[scanResult.device.id] = scanResult;
        });
      },
      onDone: _stopScan,
    );

    setState(() {
      isScanning = true;
    });
  }

  _stopScan() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
    setState(() {
      isScanning = false;
    });
  }

  _connect(BluetoothDevice d) async {
    _device = d;
    // Connect to device
    deviceConnection =
        _device?.connect(timeout: Duration(seconds: 4)).asStream().listen(
              null,
              onDone: _disconnect,
            );
    // Update the connection state immediately
    _device?.state.listen((s) {
      setState(() {
        deviceState = s;
      });
    });
    // Subscribe to connection changes
    deviceStateSubscription = _device?.state.listen((s) {
      setState(() {
        deviceState = s;
      });
      if (s == BluetoothDeviceState.connected) {
        _device?.discoverServices().then((s) {
          setState(() {
            _services = s;
            print('*** deviceId: ${_device?.id.toString()}');
            _restoreDeviceId(_device?.id.toString());
            _turnOnCharacteristicService();
          });
        });
      }
    });
  }

  _disconnect() {
    // Remove all value changed listeners
    valueChangedSubscriptions.forEach((uuid, sub) => sub.cancel());
    valueChangedSubscriptions.clear();
    deviceStateSubscription?.cancel();
    deviceStateSubscription = null;
    deviceConnection?.cancel();
    deviceConnection = null;
    _device?.disconnect();
    setState(() {
      _device = null;
    });
  }

  _readCharacteristic(BluetoothCharacteristic c) async {
    await c.read();
    setState(() {});
  }

  _writeCharacteristic(BluetoothCharacteristic c) async {
    await c.write([0x12, 0x34], withoutResponse: true);
    setState(() {});
  }

  _readDescriptor(BluetoothDescriptor d) async {
    await d.read();
    setState(() {});
  }

  _writeDescriptor(BluetoothDescriptor d) async {
    await d.write([0x12, 0x34]);
    setState(() {});
  }

  _setNotification(BluetoothCharacteristic c) async {
    if (c.isNotifying) {
      await c.setNotifyValue(false);
      // Cancel subscription
      valueChangedSubscriptions[c.uuid]?.cancel();
      valueChangedSubscriptions.remove(c.uuid);
    } else {
      await c.setNotifyValue(true);
      // ignore: cancel_subscriptions
      final sub = c.value.listen((d) {
        final String decoded = utf8.decode(d);
        _dataParser(decoded);
        // setState(() {
        //   print('onValueChanged $d');
        // });
      });
      // Add to map
      valueChangedSubscriptions[c.uuid] = sub;
    }
    setState(() {});
  }

  _refreshDeviceState(BluetoothDevice? d) async {
    var state = d?.state;
    setState(() async {
      deviceState = await state?.single;
      print('State refreshed: $deviceState');
    });
  }

  _buildScanningButton() {
    if (isConnected || state != BluetoothState.on) {
      return null;
    }
    if (isScanning) {
      return FloatingActionButton(
        child: Icon(Icons.stop),
        onPressed: _stopScan,
        backgroundColor: Colors.red,
      );
    } else {
      return FloatingActionButton(
          child: Icon(Icons.search), onPressed: _startScan);
    }
  }

  _buildScanResultTiles() {
    return scanResults.values
        .map((r) => ScanResultTile(
              result: r,
              onTap: () => _connect(r.device),
            ))
        .toList();
  }

  List<Widget> _buildServiceTiles() {
    if(_services != null) {
      return _services!
          .map(
            (s) => ServiceTile(
          service: s,
          characteristicTiles: s.characteristics
              .map(
                (c) => CharacteristicTile(
              characteristic: c,
              onReadPressed: () => _readCharacteristic(c),
              onWritePressed: () => _writeCharacteristic(c),
              onNotificationPressed: () => _setNotification(c),
              descriptorTiles: c.descriptors
                  .map(
                    (d) => DescriptorTile(
                  descriptor: d,
                  onReadPressed: () => _readDescriptor(d),
                  onWritePressed: () => _writeDescriptor(d),
                ),
              )
                  .toList(),
            ),
          )
              .toList(),
        ),
      )
          .toList();
    }
    return [];
  }

  _buildActionButtons() {
    if (isConnected) {
      return <Widget>[
        IconButton(
          icon: const Icon(Icons.cancel),
          onPressed: () => _disconnect(),
        )
      ];
    }
  }

  _buildAlertTile() {
    return Container(
      color: Colors.redAccent,
      child: ListTile(
        title: Text(
          'Bluetooth adapter is ${state.toString().substring(15)}',
          style: Theme.of(context).primaryTextTheme.subtitle1,
        ),
        trailing: Icon(
          Icons.error,
          color: Theme.of(context).primaryTextTheme.subtitle1!.color,
        ),
      ),
    );
  }

  _buildDeviceStateTile() {
    return ListTile(
        leading: (deviceState == BluetoothDeviceState.connected)
            ? const Icon(Icons.bluetooth_connected)
            : const Icon(Icons.bluetooth_disabled),
        title: Text('Device is ${deviceState.toString().split('.')[1]}.'),
        subtitle: Text('${_device?.id}'),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _refreshDeviceState(_device),
          color: Theme.of(context).iconTheme.color!.withOpacity(0.5),
        ));
  }

  _buildProgressBarTile() {
    return LinearProgressIndicator();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> tiles = [];
    if (state != BluetoothState.on) {
      tiles.add(_buildAlertTile());
    }
    if (isConnected) {
      // tiles.add(_buildDeviceStateTile());
      // tiles.addAll(_buildServiceTiles());
    } else {
      tiles.addAll(_buildScanResultTiles());
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('STM32'),
        actions: _buildActionButtons(),
      ),
      floatingActionButton: _buildScanningButton(),
      backgroundColor: Colors.blueGrey,
      body: Stack(
        children: <Widget>[
          isScanning ? _buildProgressBarTile() : Container(),
          isConnected ? _buildDataWidget() : ListView(
            children: tiles,
          )
        ],
      ),
    );
  }

  Future<void> _restoreDeviceId(String? id) async {
    final SharedPreferences prefs = await _prefs;
    prefs.setString(kMYDEVICE, id ?? '');
  }

  _turnOnCharacteristicService() {
    _services?.forEach((service) {
      service.characteristics.forEach((characteristic) {
        if(characteristic.uuid.toString() == CHARACTERISTIC_UUID) {
          _setNotification(characteristic);
        }
      });
    });
  }

  Widget _buildDataWidget() {
    return Align(
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Card(
            child: Container(
              width: 150,
              height: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    height: 10,
                  ),
                  Container(
                    width: 100,
                    height: 100,
                    child: SvgPicture.asset('images/thermometer.svg'),
                  ),
                  SizedBox(
                    height: 10,
                  ),
                  Text(
                    "Temperature",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Container(),
                  ),
                  Text(
                    _temperature,
                    style: TextStyle(fontSize: 30),
                  ),
                  SizedBox(
                    height: 10,
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Container(
              width: 150,
              height: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    height: 10,
                  ),
                  Container(
                    width: 100,
                    height: 100,
                    child: SvgPicture.asset('images/humidity.svg'),
                  ),
                  SizedBox(
                    height: 10,
                  ),
                  Text(
                    "Humidity",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Container(),
                  ),
                  Text(
                    _humidity,
                    style: TextStyle(fontSize: 30),
                  ),
                  SizedBox(
                    height: 10,
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  _dataParser(String data) {
    if (data.isNotEmpty) {
      var tempValue = data.split(",")[0];
      var humidityValue = data.split(",")[1];

      print("tempValue: $tempValue");
      print("humidityValue: $humidityValue");

      setState(() {
        _temperature = tempValue + "'C";
        _humidity = humidityValue + "%";
      });
    }
  }
}
