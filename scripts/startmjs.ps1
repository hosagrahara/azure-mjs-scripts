# mjs & worker vm setup script - run on mjs and worker VMs within a public cluster
# To launch headnode node: startmjs.ps1 headnode hostname master mjsname numworkers
# To launch worker node: startmjs.ps1 worker hostname master mjsname numworkers
# Arguments:
# hostname : the hostname that the service should advertise with.
# master: the host name where the jobmanager is running.
# mjsname: the name of the jobmanager service.
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

# Step 1. Update mdce_def for hosted license and hostname suffix
$matlabroot = FindMatlabRoot
$mdcsdir = $matlabroot + "\toolbox\distcomp\bin"

echo "config mdce_def" | trace
$configfile = $mdcsdir + "\mdce_def.bat"

$hostname = $p[1]
$master = $p[2]

# Make sure the DNS name can be resolved on all nodes
while(($t -lt 360) -and ($True -ne (Resolve-Dnsname $hostname))) {
  echo "keep contacting host dns" | trace
  Start-Sleep 10
  ipconfig /flushdns
  $t++
};
while(($t -lt 360) -and ($True -ne (Resolve-Dnsname $master))) {
  echo "keep contacting master dns" | trace
  Start-Sleep 10
  ipconfig /flushdns
  $t++
};

# Write hostname to mdce_def file
(Get-Content $configfile) | Foreach-Object {$_ -replace '^REM set HOSTNAME=.+$', ('set HOSTNAME=' + $hostname)} | Set-Content ($configfile)
(Get-Content $configfile) | Foreach-Object {$_ -replace '^set USE_MATHWORKS_HOSTED_LICENSE_MANAGER=.+$', ("set USE_MATHWORKS_HOSTED_LICENSE_MANAGER=true")} | Set-Content ($configfile)

# Step 2. Open tcp ports in firewall
echo "open tcp ports in firewall" | trace
Get-NetFirewallRule | ?{$_.Name -like "RemoteSvcAdmin*"} | Enable-NetFirewallRule
New-NetFirewallRule -Name "mdcs" -DisplayName "mdcs" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 27000-28000 -ErrorAction SilentlyContinue
New-NetFirewallRule -Name "mdcs2" -DisplayName "mdcs2" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 14350-14479 -ErrorAction SilentlyContinue
New-NetFirewallRule -Name "mdcs3" -DisplayName "mdcs3" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 443 -ErrorAction SilentlyContinue
New-NetFirewallRule -Name "mdcs_out" -DisplayName "mdcs_out" -Direction Outbound -Action Allow -Protocol TCP -LocalPort 27000-28000 -ErrorAction SilentlyContinue
New-NetFirewallRule -Name "mdcs2_out" -DisplayName "mdcs2_out" -Direction Outbound -Action Allow -Protocol TCP -LocalPort 14351-14479 -ErrorAction SilentlyContinue
New-NetFirewallRule -Name "mdcs3_out" -DisplayName "mdcs3_out" -Direction Outbound -Action Allow -Protocol TCP -LocalPort 443 -ErrorAction SilentlyContinue

# Step 3. Install & Start MDCE service
echo "install mdce service" | trace
Set-Location $mdcsdir
.\mdce.bat install 2>&1 | trace
.\mdce.bat start -clean -loglevel 6 2>&1 | trace

# Step 4. Install MJS - headnode only.
if(0 -eq $p[0].ToLower().CompareTo("headnode")) { # for headnode only
  # - Start MJS job manager
  echo "starting job manager"  | trace
  .\startjobmanager.bat -name $p[3] 2>&1 | trace
}

# Step 5. open PING
echo "opening PING" | trace
Get-NetFirewallRule | ?{$_.Name -like "FPS-ICMP*"} | Enable-NetFirewallRule

# Step 6. Block until master can be contacted, if master can be ping-ed, mjs has been setup on master
echo "contacting master" | trace
# Block until can ping, max try 10*360 seconds. If this machine IS master, it'll pass directly
while(($t -lt 360) -and ($True -ne ( Test-Connection -count 1 -computer $master -quiet ))) {
  echo "keep contacting master" | trace
  Start-Sleep 10
  $t++
};

# Step 7. Launch any workers. Both headnode and workers can share this step
$total = $p[$p.length-1] # the last argument is the # of workers
if($total -eq -1) { # -1 means auto, # of workers == # of cores
  $total = (Get-WmiObject -class win32_processor -Property "numberOfCores").NumberOfCores
}
echo "start workers (total = $total)" | trace
for($i=0;$i -lt $total;$i++) {
  $workername = "WORKER_" + $env:COMPUTERNAME + "_" + $i + "_" + $total
  echo "add worker $workername" | trace
  .\startworker.bat -jobmanagerhost $master -jobmanager $p[3] -name $workername 2>&1 | trace
}
echo "all done. exit." | trace
}

# bootstrap
$MyInvocation | Out-String | trace

foreach($arg in $args) {
	echo "calling to main with $args" | trace
	main($args)
	exit
}
