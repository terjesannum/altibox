# altibox-devices

List devices connected to your Altibox router

```
Usage: ./altibox-devices.pl --user <user> --password <password> [--verbose] [--format <raw|table>] [--output <file>]
```

```
$ ./altibox-devices.pl --user foo@bar.zot --password xxxyyyzzz
Name                IP             MAC               Connection RSSI
rockrobo            192.168.10.191 34:ce:00:e9:a2:73 WIFI24GHZ  65
Laptop              192.168.10.187 f0:4d:a2:c1:11:00 WIFI5GHZ   45
raspberrypi         192.168.10.182 dc:a6:32:1c:7b:9f WIFI5GHZ   62
Apple-TV            192.168.10.139 90:dd:5d:cb:f2:3b WIRED       0
```

Environment variables can also be used for options: `ALTIBOX_USER`, `ALTIBOX_PASSWORD`, `ALTIBOX_FORMAT`, `ALTIBOX_OUTPUT`, `ALTIBOX_VERBOSE`.
