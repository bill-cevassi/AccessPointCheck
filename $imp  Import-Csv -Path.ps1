Get-Module Microsoft.PowerShell.Management
Get-Module Microsoft.PowerShell.Core

$imp = Import-Csv -Path ./APS.CSV -Delimiter ',' 
 
$imp.Initialize()
$size = $imp.Count
$outFileName ='.\App-Down_' + (Get-Date -Format "dd-MM-yyyy") + '.csv'

for ($i = 0; $i -lt $size; $i++) {
    Write-Host 'pingando' $imp.GetValue($i).IP
    $Result = Test-Connection -TargetName ($imp.GetValue($i).IP) -Count 1
    if ($Result.Status.ToString() -EQ 'TimedOut'){
        $ApsOFF = ($imp.GetValue($i) | Select-Object -Property IP,APNAME)
        $ApsOFF | Export-Csv -Path $outFileName -NoTypeInformation -Append
        $imp.GetValue($i).IP | Out-File -FilePath .\Aps-off.txt -Append
  
    }
}

    
    

