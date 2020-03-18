# Testing the Check-Certificate plugin

Set-Location $PSScriptRoot

Write-Host 'Icinga 2 local certificates'
$rc = .\Check-Certificate.ps1 -CertPath C:\ProgramData\icinga2\var\lib\icinga2\certs -CertName *.crt -CriticalStart 2019-03-01
Write-Host "Status: ${rc}"
Write-Host

Write-Host 'Local cert stores'
$rc = .\Check-Certificate.ps1 -CertStore '*' -CertSubject '*Microsoft*'
Write-Host "Status: ${rc}"
Write-Host

Write-Host 'Testing for errors'
.\Check-Certificate.ps1 -CertPath C:\ProgramData\icinga2\var\lib\icinga2\certs -CertName ca.crt,'*.key','*.xxx' -CriticalStart 2019-03-01
Write-Host "Status: ${rc}"
Write-Host