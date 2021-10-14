param(
    [Parameter(Mandatory=$false,ParameterSetName="c",ValueFromPipeline=$false)][string[]]$Contadorping,
    [Parameter(Mandatory=$true,ParameterSetName="o",ValueFromPipeline=$false)][string[]]$ArquivoOrigem,
    [Parameter(Mandatory=$true,ParameterSetName="i",ValueFromPipeline=$false)][string[]]$ColunaIP,
    [Parameter(Mandatory=$true,ParameterSetName="d",ValueFromPipeline=$false)][string[]]$ColunaDescricao,
    [Parameter(Mandatory=$false,ParameterSetName="t",ValueFromPipeline=$false)][string[]]$Delimitador = ','
    
)

Write-Host $ArquivoOrigem

#$imp = Import-Csv -Path ./APS.CSV -Delimiter ',' 
<# arrayOrigem = Import-Csv -Path $ArquivoOrigem -Delimiter $Delimitador
 
$arrayOrigem.Initialize()
$size = $arrayOrigem.Count
$outFileName ='.\AccesPoints-Down_' + (Get-Date -Format "dd-MM-yyyy") + '.csv'

for ($i = 0; $i -lt $size; $i++) {
    Write-Host 'pingando' $arrayOrigem.GetValue($i).$ColunaIP
    $Result = Test-Connection -TargetName ($arrayOrigem.GetValue($i).$ColunaIP) -Count $Contadorping
    if ($Result.Status.ToString() -EQ 'TimedOut'){
        $ApsOFF = ($arrayOrigem.GetValue($i) | Select-Object -Property $ColunaIP,$ColunaDescricao)
        $ApsOFF | Export-Csv -Path $outFileName -NoTypeInformation -Append  
    }
}

    
    
 
 #>