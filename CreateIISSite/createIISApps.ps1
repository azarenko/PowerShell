# Set up individual EJ sites in IIS
# Run steps: 
# 1. Put this script into EasyJet directory (exp. D:\Web\easyjet\createIISApps.ps1)
# 2. Open Powershell console as administrator
# 3. Run script
# 4. If you run script from different directory, you need to specify source folder path in SrcFolder parameter

Param ([string]$SrcFolder=$PSScriptRoot)

Import-Module WebAdministration

function Setup
{
    CreateApp -AppName "mamba.local" -AppPath "$SrcFolder\mamba\Mamba.Presentation.Website" -HostName "mamba.local"
    CreateApp -AppName "availability.easyjet.local" -AppPath "$SrcFolder\stimson\Stimson.Availability.WebApi" -HostName "availability.easyjet.local"
    CreateApp -AppName "rebooking.easyjet.local" -AppPath "$SrcFolder\stimson\Stimson.Rebooking.WebApi" -HostName "rebooking.easyjet.local"
    CreateApp -AppName "mandarin.local" -AppPath "$SrcFolder\mandarin\Mandarin.Website" -HostName "mandarin.local"
    CreateApp -AppName "api.mandarin.local" -AppPath "$SrcFolder\mandarin\Mandarin.WebApi" -HostName "api.mandarin.local"
    CreateApp -AppName "dev.local" -AppPath "$SrcFolder\hydra\DevProxy" -Ssl -HostName "easyjet.local"
}

function CreateApp
{
    Param ([string]$AppName,[string]$AppPath,[switch]$Ssl=$false,[string]$HostName)

    if(!(Test-Path "IIS:\AppPools\$AppName"))
    {
        New-WebAppPool -Name "$AppName"
    }
    else
    {
        Write-Host "AppPool '$AppName' is exist"
    }
    
    if(!(Test-Path "IIS:\Sites\$AppName"))
    {
        New-WebSite -Name "$AppName" -ApplicationPool "$AppName"  -Port 80 -HostHeader "$HostName" -PhysicalPath "$AppPath" -Force                
    }
    else
    {
        Write-Host "AppSite '$AppName' is exist"
    }

    if($Ssl)
    {
        CreateSSLCert -HostName $HostName               
        if(!(Get-ChildItem IIS:\SslBindings | where-object { $_.Host -eq $HostName } | Select-Object -First 1))
        {
            New-WebBinding -name "$AppName" -Protocol https  -HostHeader "$HostName" -IP "*" -SslFlags 1
            $cert = (Get-ChildItem cert:\LocalMachine\My | where-object { $_.Subject -like "*$HostName*" } | Select-Object -First 1).Thumbprint       
            New-Item -Path "IIS:\SslBindings\*!443!$HostName" -Thumbprint $cert -SSLFlags 1
        }
    }
}

function CreateSSLCert
{
    Param ([string]$HostName)
       
    $workingRoot = "$PSScriptRoot\cert"    
    $pem = "$workingRoot\$HostName.pem"
    $pfx = "$workingRoot\$HostName.pfx"
    $password = "eatit"
    $openssl = "$workingRoot\openssl\openssl.exe"
    $sslconfig = "$PSScriptRoot\$HostName.conf"

    if(!(Test-Path $workingRoot))
    {
        $openSSLZipUrl = "https://indy.fulgan.com/SSL/openssl-1.0.2q-x64_86-win64.zip"
        $openSSLzipFile = "$workingRoot\openssl.zip"
        $openSSLFolder = "$workingRoot\openssl"        

        New-Item -Path $workingRoot -ItemType Directory

        if(!(Test-Path $openSSLzipFile))
        {
            (New-Object System.Net.WebClient).DownloadFile($openSSLZipUrl, $openSSLzipFile)
        }

        if(!(Test-Path $openSSLFolder))
        {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($openSSLzipFile, $openSSLFolder)
        }
    }

    if(!(Test-Path $pem))
    {        
"[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
C = CH
ST = VD
L = Bristol
O = Valtech UK
OU = EXTC
CN = $HostName
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = $HostName" | out-file -encoding ASCII $sslconfig 
        & $openssl req -x509 -nodes -days 3560 -newkey rsa:2048 -keyout $pem -out $pem -config $sslconfig
    }

    if(!(Test-Path $pfx) -and (Test-Path $pem))
    {        
        & $openssl pkcs12 -export -out $pfx -in $pem -name "$HostName" -passout "pass:$password"
    }

    if(Test-Path $pfx)
    {
        $securePassword = ConvertTo-SecureString -AsPlainText -Force $password
        Import-PfxCertificate -FilePath $pfx -Password $securePassword -Exportable -CertStoreLocation "cert:\LocalMachine\Root"
        Import-PfxCertificate -FilePath $pfx -Password $securePassword -Exportable -CertStoreLocation "cert:\LocalMachine\My"   
    }        
}

Setup