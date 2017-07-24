Param(
    [Parameter(Mandatory=$true)][string]$devstackIP,
    [string]$branchName='master'
)

$scriptLocation = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
. "$scriptLocation\config.ps1"
. "$scriptLocation\utils.ps1"

$hasNova = Test-Path $buildDir\nova
$hasNeutron = Test-Path $buildDir\neutron
$hasNeutronTemplate = Test-Path $neutronTemplate
$hasNovaTemplate = Test-Path $novaTemplate
$hasConfigDir = Test-Path $configDir
$hasBinDir = Test-Path $binDir
$hasMkisoFs = Test-Path $binDir\mkisofs.exe
$hasQemuImg = Test-Path $binDir\qemu-img.exe

Add-Type -AssemblyName System.IO.Compression.FileSystem

$pip_conf_content = @"
[global]
index-url = http://10.20.1.8:8080/cloudbase/CI/+simple/
[install]
trusted-host = 10.20.1.8
"@

$ErrorActionPreference = "Stop"

destroy_planned_vms

if ($hasBinDir -eq $false){
    mkdir $binDir
}

if (($hasMkisoFs -eq $false) -or ($hasQemuImg -eq $false)){
        Invoke-WebRequest -Uri "http://10.20.1.14:8080/openstack_bin.zip" -OutFile "$bindir\openstack_bin.zip"
        [System.IO.Compression.ZipFile]::ExtractToDirectory("$bindir\openstack_bin.zip", "$bindir")
        Remove-Item -Force "$bindir\openstack_bin.zip"
}

if ($hasNovaTemplate -eq $false){
    Throw "Nova template not found"
}

if ($hasNeutronTemplate -eq $false){
    Throw "Neutron template not found"
}

git config --global user.email "hyper-v_ci@microsoft.com"
git config --global user.name "Hyper-V CI"


ExecRetry {
    GitClonePull "$buildDir\nova" "https://github.com/openstack/nova.git" $branchName
}
ExecRetry {
    GitClonePull "$buildDir\neutron" "https://github.com/openstack/neutron.git" $branchName
}
ExecRetry {
    GitClonePull "$buildDir\networking-hyperv" "https://github.com/openstack/networking-hyperv.git" $branchName
}
ExecRetry {
    GitClonePull "$buildDir\compute-hyperv" "https://github.com/openstack/compute-hyperv.git" $branchName
}
ExecRetry {
    GitClonePull "$buildDir\requirements" "https://git.openstack.org/openstack/requirements.git" $branchName
}
ExecRetry {
    GitClonePull "$buildDir\os-win" "https://git.openstack.org/openstack/os-win.git" $branchName
}

$hasLogDir = Test-Path $openstackLogs
if ($hasLogDir -eq $false){
    mkdir $openstackLogs
}

pushd C:\
if (Test-Path $pythonArchive)
{
    Remove-Item -Force $pythonArchive
}
Invoke-WebRequest -Uri http://10.20.1.14:8080/python.zip -OutFile $pythonArchive
if (Test-Path $pythonDir)
{
    #Remove-Item -Recurse -Force $pythonDir
    Cmd /C "rmdir /S /Q $pythonDir"
}

# At some point, we were unarchiving the image at an unexpected destination.
if (Test-Path "C:\ws2012_r2_kvm_eval.vhdx") {
    Rename-Item "C:\ws2012_r2_kvm_eval.vhdx" $windowsImagePath
}
elseif (! (Get-VHD $windowsImagePath -ErrorAction SilentlyContinue)){
    if (Test-Path $windowsImagePath) { # in case the vhd exists but it is not valid
        rm $windowsImagePath
    }
    Write-Host "Fetching Windows image."
    if (! (Test-Path $windowsImagePathGz)) {

        $retrycount = 1
        $completed = $false
        while (-not $completed -And $retrycount -lt 5) {
            Write-Host "Attempt $retrycount to download image file"
            (New-Object System.Net.WebClient).DownloadFile($tempWindowsImageUrl, $windowsImagePathGz)
            if ( (Get-FileHash -Algorithm MD5 $windowsImagePathGz).hash -eq "C349E9D14305291033CA30D26ABFE3FE") {
                Write-Host "Hash matched"
                $completed = $true
            }
            else {
                $retrycount++
                Write-Host "Hash mismatched, retrying"
            }
        }
    }

    [System.IO.Compression.ZipFile]::ExtractToDirectory($windowsImagePathGz, $openstackDir)
    Rename-Item C:\OpenStack\ws2012_r2_kvm_eval.vhdx $windowsImagePath
}
else {
    write-host "$windowsImage already exists at $windowsImagePath."
}

Write-Host "Ensure Python folder is up to date"
Write-Host "Extracting archive.."
[System.IO.Compression.ZipFile]::ExtractToDirectory("C:\$pythonArchive", "C:\")

$hasPipConf = Test-Path "$env:APPDATA\pip"
if ($hasPipConf -eq $false){
    mkdir "$env:APPDATA\pip"
}
else 
{
    Remove-Item -Force "$env:APPDATA\pip\*"
}
Add-Content "$env:APPDATA\pip\pip.ini" $pip_conf_content

& easy_install -U pip
& pip install -U setuptools
& pip install -U --pre pymi
& pip install cffi
& pip install numpy
& pip install pycrypto
& pip install amqp==1.4.9
popd

$hasPipConf = Test-Path "$env:APPDATA\pip"
if ($hasPipConf -eq $false){
    mkdir "$env:APPDATA\pip"
}
else 
{
    Remove-Item -Force "$env:APPDATA\pip\*"
}
Add-Content "$env:APPDATA\pip\pip.ini" $pip_conf_content

cp $templateDir\distutils.cfg C:\Python27\Lib\distutils\distutils.cfg

function cherry_pick($commit) {
    $eapSet = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git cherry-pick $commit

    if ($LastExitCode) {
        echo "Ignoring failed git cherry-pick $commit"
        git checkout --force
    }
    $ErrorActionPreference = $eapSet
}

ExecRetry {
    pushd "$buildDir\requirements"
    & pip install -c upper-constraints.txt -U pbr virtualenv httplib2 prettytable>=0.7 setuptools
    & pip install -c upper-constraints.txt -U .
    if ($LastExitCode) { Throw "Failed to install openstack/requirements from repo" }
    popd
}

ExecRetry {
    pushd $buildDir\networking-hyperv
    & update-requirements.exe --source $buildDir\requirements .
    & pip install -c $buildDir\requirements\upper-constraints.txt -U .
    if ($LastExitCode) { Throw "Failed to install networking-hyperv from repo" }
    popd
}

ExecRetry {
    pushd $buildDir\neutron
    git fetch git://git.openstack.org/openstack/neutron refs/changes/33/468833/1
    cherry_pick FETCH_HEAD
    & update-requirements.exe --source $buildDir\requirements .
    & pip install -c $buildDir\requirements\upper-constraints.txt -U .
    if ($LastExitCode) { Throw "Failed to install neutron from repo" }
    popd
}

ExecRetry {
    pushd $buildDir\nova
    if ($branchName -eq 'master') {
        # This patch fixes things with InstanceMetadata
        git fetch git://git.openstack.org/openstack/nova refs/changes/25/479325/1
        cherry_pick FETCH_HEAD
    }
    Write-Host "Installing openstack/nova..."
    & update-requirements.exe --source $buildDir\requirements .
    & pip install -c $buildDir\requirements\upper-constraints.txt -U .
    if ($LastExitCode) { Throw "Failed to install nova fom repo" }
    popd
}

ExecRetry {
    pushd $buildDir\compute-hyperv
    & update-requirements.exe --source $buildDir\requirements .
    & pip install -c $buildDir\requirements\upper-constraints.txt -U .
    if ($LastExitCode) { Throw "Failed to install compute-hyperv from repo" }
    popd
}

ExecRetry {
    pushd "$buildDir\os-win"
    Write-Host "Installing OpenStack/os-win..."
    & update-requirements.exe --source $buildDir\requirements .
    & edit-constraints.exe $buildDir\requirements\upper-constraints.txt -- os-win ""
    & pip install -c $buildDir\requirements\upper-constraints.txt -U . 
    if ($LastExitCode) { Throw "Failed to install openstack/os-win from repo" }
    popd
}

pip install setuptools==33.1.1 oslo.log==3.23.0
pip install kombu==4.0.1
pip install amqp==2.1.3
 
$cpu_array = ([array](gwmi -class Win32_Processor))
$cores_count = $cpu_array.count * $cpu_array[0].NumberOfCores

$novaConfig = (gc "$templateDir\nova.conf").replace('[DEVSTACK_IP]', "$devstackIP").Replace('[LOGDIR]', "$openstackLogs").Replace('[RABBITUSER]', $rabbitUser)
$neutronConfig = (gc "$templateDir\neutron_hyperv_agent.conf").replace('[DEVSTACK_IP]', "$devstackIP").Replace('[LOGDIR]', "$openstackLogs").Replace('[RABBITUSER]', $rabbitUser).Replace('[CORES_COUNT]', "$cores_count")

if (($branchName -ne 'stable/liberty') -and ($branchName -ne 'stable/mitaka')) {
    $novaConfig = $novaConfig.replace('network_api_class', '#network_api_class')
}

Set-Content C:\OpenStack\etc\nova.conf $novaConfig
if ($? -eq $false){
    Throw "Error writting $templateDir\nova.conf"
}

Set-Content C:\OpenStack\etc\neutron_hyperv_agent.conf $neutronConfig
if ($? -eq $false){
    Throw "Error writting neutron_hyperv_agent.conf"
}

cp "$templateDir\policy.json" "$configDir\"
cp "$templateDir\interfaces.template" "$configDir\"

$hasNovaExec = Test-Path c:\Python27\Scripts\nova-compute.exe
if ($hasNovaExec -eq $false){
    Throw "No nova exe found"
}

$hasNeutronExec = Test-Path "c:\Python27\Scripts\neutron-hyperv-agent.exe"
if ($hasNeutronExec -eq $false){
    Throw "No neutron exe found"
}

# this file is used by oslo reports section in nova.conf
echo $null >> C:\OpenStack\gmr_manila_trigger

Write-Host "Starting the services"

Write-Host "Starting nova-compute service"
Try
{
    Start-Service nova-compute
}
Catch
{
    $proc = Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\nova-compute.exe" -ArgumentList "--config-file $configDir\nova.conf"
    Start-Sleep -s 30
    if (! $proc.HasExited) {Stop-Process -Id $proc.Id -Force}
    Throw "Can not start the nova-compute service"
}
Start-Sleep -s 30
if ($(get-service nova-compute).Status -eq "Stopped")
{
    Write-Host "We try to start:"
    Write-Host Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\nova-compute.exe" -ArgumentList "--config-file $configDir\nova.conf"
    Try
    {
    	$proc = Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\nova-compute.exe" -ArgumentList "--config-file $configDir\nova.conf"
    }
    Catch
    {
    	Throw "Could not start the process manually"
    }
    Start-Sleep -s 30
    if (! $proc.HasExited)
    {
    	Stop-Process -Id $proc.Id -Force
    	Throw "Process started fine when run manually."
    }
    else
    {
    	Throw "Can not start the nova-compute service. The manual run failed as well."
    }
}

Write-Host "Starting neutron-hyperv-agent service"
Try
{
    Start-Service neutron-hyperv-agent
}
Catch
{
    $proc = Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\neutron-hyperv-agent.exe" -ArgumentList "--config-file $configDir\neutron_hyperv_agent.conf"
    Start-Sleep -s 30
    if (! $proc.HasExited) {Stop-Process -Id $proc.Id -Force}
    Throw "Can not start the neutron-hyperv-agent service"
}
Start-Sleep -s 30
if ($(get-service neutron-hyperv-agent).Status -eq "Stopped")
{
    Write-Host "We try to start:"
    Write-Host Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\neutron-hyperv-agent.exe" -ArgumentList "--config-file $configDir\neutron_hyperv_agent.conf"
    Try
    {
    	$proc = Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\neutron-hyperv-agent.exe" -ArgumentList "--config-file $configDir\neutron_hyperv_agent.conf"
    }
    Catch
    {
    	Throw "Could not start the process manually"
    }
    Start-Sleep -s 30
    if (! $proc.HasExited)
    {
    	Stop-Process -Id $proc.Id -Force
    	Throw "Process started fine when run manually."
    }
    else
    {
    	Throw "Can not start the neutron-hyperv-agent service. The manual run failed as well."
    }
}
