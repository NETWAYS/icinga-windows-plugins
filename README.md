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