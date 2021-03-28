import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: 'Flutter Demo BLE'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  final FlutterBlue flutterBlue = FlutterBlue.instance;
  final List<BluetoothDevice> devicesList = [];
  final Map<Guid, List<int>> readValues = new Map<Guid, List<int>>();
  BluetoothDevice _connectedDevice;
  List<BluetoothService> _services;
  final _writeController = TextEditingController();

  _addDeviceToList(final BluetoothDevice device) {
      if(!devicesList.contains(device)) {
        setState(() {
          devicesList.add(device);
        });
      }
  }

  @override
  void initState() {
    super.initState();
    flutterBlue.connectedDevices.asStream().listen((List<BluetoothDevice> devices) {
      for(BluetoothDevice device in devices) {
        _addDeviceToList(device);
      }
    });
    flutterBlue.scanResults.listen((List<ScanResult> results) {
      for(ScanResult result in results) {
        _addDeviceToList(result.device);
      }
    });
    flutterBlue.startScan();
  }

  Widget _buildDeviceItem(BluetoothDevice device) {
    return Container(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(device.name == '' ? '(unknown device)' : device.name),
                Text(device.id.toString()),
              ],
            ),
          ),
          TextButton(
            child: Text(
              'Connect',
              style: TextStyle(color: Colors.white),
            ),
            style: ButtonStyle(
              backgroundColor: MaterialStateProperty.all(Colors.blue),
            ),
            onPressed: () async {
              flutterBlue.stopScan();
              try {
                await device.connect();
              } catch (e) {
                if (e.code != 'already_connected') {
                  throw e;
                }
              } finally {
                _services = await device.discoverServices();
              }
              setState(() {
                _connectedDevice = device;
              });
            },
          ),
        ],
      ),
    );
  }

  ListView _buildListViewOfDevices() {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) => _buildDeviceItem(devicesList[index]),
      separatorBuilder: (context, index) => Divider(),
      itemCount: devicesList.length,
    );
  }

  ListView _buildView() {
    if (_connectedDevice != null) {
      return _buildConnectDeviceView();
    }
    return _buildListViewOfDevices();
  }

  ListView _buildConnectDeviceView() {
    List<Container> containers = [];

    for (BluetoothService service in _services) {
      List<Widget> characteristicsWidget = [];
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        characteristic.value.listen((value) {
          print(value);
        });
        characteristicsWidget.add(
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(characteristic.uuid.toString(), style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Row(
                  children: <Widget>[
                    ..._buildReadWriteNotifyButton(characteristic),
                  ],
                ),
                Row(
                  children: <Widget>[
                    Text('Value: ' +
                        readValues[characteristic.uuid].toString()),
                  ],
                ),
                Divider(),
              ],
            ),
          ),
        );
      }
      containers.add(
        Container(
          child: ExpansionTile(
              title: Text(service.uuid.toString()),
              children: characteristicsWidget),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: <Widget>[
        ...containers,
      ],
    );

  }

List<ButtonTheme> _buildReadWriteNotifyButton(
    BluetoothCharacteristic characteristic) {
  List<ButtonTheme> buttons = [];

  if (characteristic.properties.read) {
    buttons.add(
      ButtonTheme(
        minWidth: 10,
        height: 20,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ElevatedButton(
            child: Text('READ', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                var sub = characteristic.value.listen((value) {
                  setState(() {
                    readValues[characteristic.uuid] = value;
                  });
                });
                await characteristic.read();
                sub.cancel();
              },
          ),
        ),
      ),
    );
  }
  if (characteristic.properties.write) {
    buttons.add(
      ButtonTheme(
        minWidth: 10,
        height: 20,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ElevatedButton(
            child: Text('WRITE', style: TextStyle(color: Colors.white)),
            onPressed: () async {
              await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text("Write"),
                      content: Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: _writeController,
                            ),
                          ),
                        ],
                      ),
                      actions: <Widget>[
                        TextButton(
                          child: Text("Send"),
                          onPressed: () {
                            characteristic.write(utf8.encode(_writeController.value.text));
                            Navigator.pop(context);
                          },
                        ),
                        TextButton(
                          child: Text("Cancel"),
                          onPressed: () {
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    );
                  });
            },
          ),
        ),
      ),
    );
  }
  if (characteristic.properties.notify) {
    buttons.add(
      ButtonTheme(
        minWidth: 10,
        height: 20,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ElevatedButton(
            child: Text('NOTIFY', style: TextStyle(color: Colors.white)),
            onPressed: () async {
              characteristic.value.listen((value) {
                readValues[characteristic.uuid] = value;
              });
              await characteristic.setNotifyValue(true);
            },
          ),
        ),
      ),
    );
  }

  return buttons;
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: _buildView(),
    );
  }
}
