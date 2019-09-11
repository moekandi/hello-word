 #https://4sysops.com/archives/install-and-configure-an-ftp-server-with-powershell/
# Install the Windows feature for FTP
Install-WindowsFeature Web-FTP-Server -IncludeAllSubFeature -IncludeManagementTools

# Import the module
Import-Module WebAdministration

# Create the FTP site
$FTPSiteName = 'Automated FTP Site'
$FTPRootDir = 'C:\FTPRoot'
$FTPPort = 21
New-WebFtpSite -Name $FTPSiteName -Port $FTPPort -PhysicalPath $FTPRootDir -IPAddress "*" -Force

# Create the Domain Windows group
$FTPUserGroupName = 'FTP-USERS'
invoke-Command -ComputerName server2019 -Scriptblock { New-adgroup -Name $USING:FTPUserGroupName -GroupScope Global -OtherAttributes @{description="FTP Group created by automation"} }

# Create an FTP user
$FTPUser = 'FTP USER' 
Invoke-Command -ComputerName Server2019 -ScriptBlock { New-ADUser -Name "$USING:FTPUser" -GivenName "FTP" -Surname "User" -SamAccountName "FTP.User" -UserPrincipalName "FTP.User" -AccountPassword (ConvertTo-SecureString 'Password1' -AsPlainText -force) -passThru -enabled $true } 

# Add an FTP user to the group FTP Users
Invoke-Command -ComputerName Server2019 -ScriptBlock {Add-ADGroupMember -Identity "$USING:FTPUserGroupName" -Members "FTP.User"}

# Enable basic authentication on the FTP site
$FTPSitePath = "IIS:\Sites\$FTPSiteName"
$BasicAuth = 'ftpServer.security.authentication.basicAuthentication.enabled'
Set-ItemProperty -Path $FTPSitePath -Name $BasicAuth -Value $True
# Add an authorization read rule for FTP Users.
$Param = @{
    Filter   = "/system.ftpServer/security/authorization"
    Value    = @{
        accessType  = "Allow"
        roles       = "$FTPUserGroupName"
        permissions = "Read, Write"
    }
    PSPath   = 'IIS:\'
    Location = $FTPSiteName
}
Add-WebConfiguration @param

#Sets Folder permissions  
$SSLPolicy = @(
    'ftpServer.security.ssl.controlChannelPolicy',
    'ftpServer.security.ssl.dataChannelPolicy'
)
Set-ItemProperty -Path $FTPSitePath -Name $SSLPolicy[0] -Value $false
Set-ItemProperty -Path $FTPSitePath -Name $SSLPolicy[1] -Value $false


$UserAccount = New-Object System.Security.Principal.NTAccount("$FTPUserGroupName")
$AccessRule = [System.Security.AccessControl.FileSystemAccessRule]::new($UserAccount,
    'FullControl',
    'ContainerInherit,ObjectInherit',
    'None',
    'Allow'
)

if( -Not (Test-Path -Path $FTPRootDir ) )
{
    New-Item -ItemType directory -Path $FTPRootDir

}

$ACL = Get-Acl -Path $FTPRootDir
$ACL.SetAccessRule($AccessRule)
$ACL | Set-Acl -Path $FTPRootDir

# Restart the FTP site for all changes to take effect
Restart-WebItem "IIS:\Sites\$FTPSiteName" -Verbose 
 
 