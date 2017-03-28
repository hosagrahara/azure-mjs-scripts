# mjs & worker vm setup script - run on mjs and worker VMs within a public cluster
# To launch headnode node: startmjs.ps1 headnode hostname mjsname headnodehost numworkers
# To launch worker node: startmjs.ps1 worker hostname mjsname headnodehost numworkers
# Arguments:
# hostname : the hostname of the VM to use with the mdce service.
# mjsname: the name of the MATLAB job scheduler.
# headnodehost: the host name where the MATLAB job scheduler is running.
# numworkers: the number of workers to start on the machine. -1 starts as many workers as cores.

function trace() {
    param(
    [Parameter(
        Position=0,
        Mandatory=$true,
        ValueFromPipeline=$true)
    ]
    [String[]]$log
    )

    filter timestamp {"$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss.fff'): $_"}
    if((Test-Path variable:logfile) -eq $false)
    {
        $datetimestr = (Get-Date).ToString('yyyy-MM-dd-HH-mm-ss')
        $script:logfile = "$env:windir\Temp\MDCSLog-$datetimestr.log"
    }
    $log | timestamp | Out-File -Confirm:$false -FilePath $script:logfile -Append
}

function FindMatlabRoot() {
    $computername = $env:computername
    $MatlabKey="SOFTWARE\\MathWorks\\MATLAB"
    $reg=[microsoft.win32.registrykey]::OpenRemoteBaseKey('LocalMachine',$computername) 
    $regkey=$reg.OpenSubKey($MatlabKey) 
    $subkeys=$regkey.GetSubKeyNames() 
    $matlabroot = ""
    foreach($key in $subkeys){
        $thisKey=$MatlabKey + "\\" + $key 
        $thisSubKey=$reg.OpenSubKey($thisKey)
        $thisroot = $thisSubKey.GetValue("MATLABROOT")
        if($matlabroot -lt $thisroot) {
            $matlabroot = $thisroot
        }
    } 
    return $matlabroot
}

function main($p) {

whoami | trace

# Parse inputs
$currentdir = $pwd
$nodetype = $p[0]
$hostname = $p[1]
$mjsname = $p[2]
$mjshost = $p[3]
$numworkers = $p[4]

# Step 1. Make sure the DNS names can be resolved on all nodes
while(($t -lt 360) -and ($True -ne (Resolve-Dnsname $hostname))) {
  echo "keep contacting host dns" | trace
  Start-Sleep 10
  ipconfig /flushdns
  $t++
};
while(($t -lt 360) -and ($True -ne (Resolve-Dnsname $mjshost))) {
  echo "keep contacting headnode dns" | trace
  Start-Sleep 10
  ipconfig /flushdns
  $t++
};

# Add firewall exceptions for matlab
echo "config firewall" | trace
Get-NetFirewallRule | ?{$_.Name -like "RemoteSvcAdmin*"} | Enable-NetFirewallRule
New-NetFirewallRule -Name "mdcs_jobmanager" -DisplayName "mdcs_jobmanager" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 27000-28000
New-NetFirewallRule -Name "mdcs_workers" -DisplayName "mdcs_workers" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 14350-14479

# Step 2. Install & Start MDCE service
$matlabroot = FindMatlabRoot
$mdcsdir = $matlabroot + "\toolbox\distcomp\bin"

$mdceloglevel = 6
$mdcecommand = "-clean"
$mdcecommand = $mdcecommand + " -allserversocketsincluster"
$mdcecommand = $mdcecommand + " -requireweblicensing -ondemand"
$mdcecommand = $mdcecommand + " -workerproxiespoolconnections"
$mdcecommand = $mdcecommand + " -enablepeerlookup"
$mdcecommand = $mdcecommand + " -untrustedclients"
$mdcecommand = $mdcecommand + " -loglevel " + $mdceloglevel
$mdcecommand = $mdcecommand + " -hostname " + $hostname

echo "install mdce service" | trace
Set-Location $mdcsdir
Invoke-Expression ".\mdce.bat install -clean 2>&1" | trace
Invoke-Expression ".\mdce.bat start $mdcecommand 2>&1" | trace

# Step 3. Install MJS - headnode only.
if(0 -eq $p[0].ToLower().CompareTo("headnode")) { # for headnode only
  # - Start MJS job manager
  echo "starting job manager"  | trace
  Invoke-Expression ".\startjobmanager.bat -name $mjsname 2>&1" | trace
}

# Step 4. Launch any workers. Both headnode and workers can share this step
if($numworkers -eq -1) { # -1 means auto, # of workers == # of cores
  $numworkers = (Get-WmiObject -class win32_processor -Property "numberOfCores").NumberOfCores
}
echo "start workers (numworkers = $numworkers)" | trace
Invoke-Expression ".\startworker.bat -jobmanagerhost $mjshost -jobmanager $mjsname -num $numworkers 2>&1" | trace

Set-Location $currentdir

echo "all done. exit." | trace
}

foreach($arg in $args) {
	echo "calling to main with $args" | trace
	main($args)
	exit
}
