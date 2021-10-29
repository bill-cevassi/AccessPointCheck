param(
    [Parameter(ParameterSetName="ContadorPing")][string[]]$ContadorPing,
    [Parameter(Mandatory,ParameterSetName="ArquivoOrigem")][string[]]$ArquivoOrigem,
    [Parameter(Mandatory,ParameterSetName="ColunaIP")][string[]]$ColunaIP,
    [Parameter(ParameterSetName="ColunaDescricao")][string[]]$ColunaDescricao,
    [Parameter(ParameterSetName="Delimitador")][string[]]$Delimitador
)

Write-Host $ArquivoOrigem

#$imp = Import-Csv -Path ./APS.CSV -Delimiter ',' 
$#arrayOrigem = Import-Csv -Path $ArquivoOrigem -Delimiter $Delimitador
$arrayOrigem = Import-Csv -Path ./APS.CSV -Delimiter ',' 


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

    
    
 
 