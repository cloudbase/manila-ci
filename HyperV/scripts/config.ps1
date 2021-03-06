##
#Hyper-V config
##

$openstackDir = "C:\OpenStack"
$baseDir = "$openstackDir\manila-ci\HyperV"
$scriptdir = "$baseDir\scripts"
$configDir = "$openstackDir\etc"
$templateDir = "$baseDir\templates"
$buildDir = "$openstackDir\build"
$binDir = "$openstackDir\bin"
$novaTemplate = "$templateDir\nova.conf"
$neutronTemplate = "$templateDir\neutron_hyperv_agent.conf"
$hostname = hostname
$rabbitUser = "stackrabbit"
$pythonDir = "C:\Python27"
$pythonArchive = "python.zip"
$pythonTar = "python27new.tar"
$pythonExec = "$pythonDir\python.exe"
$openstackLogs="$openstackDir\Logs"
$eventlogPath="$openstackLogs\Eventlog"
$eventlogcsspath = "$templateDir\eventlog_css.txt"
$eventlogjspath = "$templateDir\eventlog_js.txt"
$downloadLocation = "http://10.20.1.14:8080/"

$windowsImage = "ws2012r2.vhdx.zip"
$windowsImagePathGz = "C:\OpenStack\ws2012r2.vhdx.zip"
$windowsImagePath = "C:\OpenStack\ws2012r2.vhdx"
$tempWindowsImageUrl = "http://10.20.1.14:8080/ws2012r2.vhdx.zip"
$windowsImageUrl = "$downloadLocation/$windowsImage"
