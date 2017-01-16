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

$pip_conf_content = @"
[global]
index-url = http://10.0.110.1:8080/cloudbase/CI/+simple/
[install]
trusted-host = 10.0.110.1
"@

$ErrorActionPreference = "Stop"

destroy_planned_vms

if ($hasBinDir -eq $false){
    mkdir $binDir
}

if (($hasMkisoFs -eq $false) -or ($hasQemuImg -eq $false)){
    Invoke-WebRequest -Uri "http://10.0.110.1/openstack_bin.zip" -OutFile "$bindir\openstack_bin.zip"
    if (Test-Path "C:\Program Files\7-Zip\7z.exe"){
        pushd $bindir
        & "C:\Program Files\7-Zip\7z.exe" x -y "$bindir\openstack_bin.zip"
        Remove-Item -Force "$bindir\openstack_bin.zip"
        popd
    } else {
        Throw "Required binary files (mkisofs, qemuimg etc.)  are missing"
    }
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

$hasLogDir = Test-Path $openstackLogs
if ($hasLogDir -eq $false){
    mkdir $openstackLogs
}

$hasConfigDir = Test-Path $remoteConfigs\$hostname
if ($hasConfigDir -eq $false){
    mkdir $remoteConfigs\$hostname
}

pushd C:\
if (Test-Path $pythonArchive)
{
    Remove-Item -Force $pythonArchive
}
Invoke-WebRequest -Uri http://10.0.110.1/python27new.tar.gz -OutFile $pythonArchive
if (Test-Path $pythonTar)
{
    Remove-Item -Force $pythonTar
}
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

    unarchive $windowsImagePathGz $openstackDir
    Rename-Item C:\OpenStack\ws2012_r2_kvm_eval.vhdx $windowsImagePath
}
else {
    write-host "$windowsImage already exists at $windowsImagePath."
}

Write-Host "Ensure Python folder is up to date"
Write-Host "Extracting archive.."
& "C:\Program Files\7-Zip\7z.exe" x -y "$pythonArchive"
& "C:\Program Files\7-Zip\7z.exe" x -y "$pythonTar"

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

#cp $templateDir\distutils.cfg C:\Python27\Lib\distutils\distutils.cfg

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
    & update-requirements.exe --source $buildDir\requirements .
    & pip install -c $buildDir\requirements\upper-constraints.txt -U .
    if ($LastExitCode) { Throw "Failed to install neutron from repo" }
    popd
}

ExecRetry {
    pushd $buildDir\nova
    & update-requirements.exe --source $buildDir\requirements .
    if ($branchName -eq 'master') {
        # This patch fixes os_type image property requirement
        git fetch https://review.openstack.org/openstack/nova refs/changes/26/379326/1
        cherry_pick FETCH_HEAD
    }
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

#cp "$templateDir\policy.json" "$configDir\"
cp \\$devstackIP\openstack\policy.json "$configDir\"
#cp "$templateDir\interfaces.template" "$configDir\"

$hasNovaExec = Test-Path c:\Python27\Scripts\nova-compute.exe
if ($hasNovaExec -eq $false){
    Throw "No nova exe found"
}

$hasNeutronExec = Test-Path "c:\Python27\Scripts\neutron-hyperv-agent.exe"
if ($hasNeutronExec -eq $false){
    Throw "No neutron exe found"
}


Remove-Item -Recurse -Force "$remoteConfigs\$hostname\*"
Copy-Item -Recurse $configDir "$remoteConfigs\$hostname"

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
