Icinga Windows Plugins
======================

PowerShell plugins for Icinga Monitoring on Windows

This is likely a temporary implementation. Most checks will be implemented in a general PowerShell module for Windows:
https://github.com/LordHepipud/icinga-module-windows

### Check-Printer-Status

```
powershell.exe .\Check-Print-Spooler.ps1 -Ignore "Fax,OneNote,'Send To OneNote 2016'" -NoneIsError -UseCIM
OK - All 2 printers are fine
[OK] Microsoft XPS Document Writer - Status=Idle Info=Not Applicable JobCount=0
[OK] Microsoft Print to PDF - Status=Idle Info=Not Applicable JobCount=0
```

### Check-DHCP-Server

```
powershell.exe .\Check-DHCP-Server.ps1 -WarnFreeLeases 20 -CritFreeLeases 10 -WarnUsage 80 -CritUsage 90
OK - All 2 DHCP scopes are fine
[OK] LAN (172.17.1.0) InUse=72 (7%) Free=956 Reserved=68
[OK] DMZ (172.17.2.0) InUse=124 (50%) Free=126 Reserved=26
| LAN_inuse=72 LAN_free=956 LAN_reserved=68 ...
```