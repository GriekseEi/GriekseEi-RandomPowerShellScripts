<#
    .SYNOPSIS
        Windows Supermodel emulator + SpikeOut install wizard script
    .DESCRIPTION
        Sets up the Supermodel emulator and shortcuts to easily pick up and play both versions of SpikeOut. The user is given the choice of
        what launch options to pick (window mode, widescreen enabled, etc.). 
        
        In addition the user can choose to integrate SpikeOut as a shortcut in their Steam Library, which also allows us to supply a 
        custom Steam Input controller config that allows for more macros and button shortcuts than what the native Supermodel input 
        scheme would allow. If Steam isn't installed on the host system, then standard desktop shortcuts for SpikeOut will be made.
    .NOTES
        - Designed to work with the default PowerShell installation on most WIndows systems (PS 5.1) for total out-of-the-box compatibility.

        - This script does not supply the SpikeOut ROMs. For legal reasons these have to be found yourself and placed in the ROMs directory of
        the Supermodel folder. 

        - The Steam Input version of the Supermodel.ini config has all relevant joystick inputs scrubbed to avoid issues related to both 
        Supermodel and Steam Input firing the same input simultaneously which *may* cause issues.

        Author: testament_enjoyment
    .LINK
        https://supermodel3.com/
    .LINK
        https://developer.valvesoftware.com/wiki/VDF
    .LINK 
        https://developer.valvesoftware.com/wiki/Binary_VDF
#>

#region Global Variables

$oldErrorActionPreference = $ErrorActionPreference

$InformationPreference = 'Continue'
$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# URLs for various resources we need to download
$BASE_SUPERMODEL_URI                = 'https://supermodel3.com/'
$SUPERMODEL_STEAM_CONFIG_URI        = 'https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/main/Setup-SpikeOut/resources/steamconfig/Supermodel.ini'
$SUPERMODEL_NONSTEAM_CONFIG_URI     = 'https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/main/Setup-SpikeOut/resources/nonsteamconfig/Supermodel.ini'
$SPIKEOUT_STEAM_INPUT_CONFIG_URI    = 'https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/main/Setup-SpikeOut/resources/supermodel%20-%20spikeout%20gamepad%20(powershell%20setup)_0.vdf'
$SPIKEOUT_ICO_URI                   = 'https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/main/Setup-SpikeOut/resources/spikeout.ico'
$SPIKEOFE_ICO_URI                   = 'https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/main/Setup-SpikeOut/resources/spikeofe.ico'
$SPIKEOUT_CONTROLS_URI              = 'https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/main/Setup-SpikeOut/resources/spikeout_controls_howto.jpg'

# Values of the type bytes used in binary VDFs to signify the type of the next value. See the Binary VDF documentation
$global:TYPE_MAP       = [byte] 0
$global:TYPE_STRING    = [byte] 1
$global:TYPE_INT       = [byte] 2
$global:TYPE_FLOAT     = [byte] 3
$global:TYPE_LONG      = [byte] 7
$global:TYPE_MAPEND    = [byte] 8

#endregion

#region Binary VDF functions

#region Binary VDF Read fynctions

class BufferReader {
    [byte[]] $Buffer
    [int] $Offset

    BufferReader([byte[]]$Buffer, [int]$Offset) {
        $this.Buffer = $Buffer
        $this.Offset = $Offset
    }

    [string] ReadNextString( [System.Text.Encoding] $Encoding) {
        $nullTerminator = [System.Array]::IndexOf($this.Buffer, $global:TYPE_MAP, $this.Offset)

        if ($nullTerminator -eq -1) {
            throw [System.IndexOutOfRangeException] "Could not find null terminating byte for string"
        }

        $length = $nullTerminator - $this.Offset
        $val = $Encoding.GetString($this.Buffer, $this.Offset, $length)
        $this.Offset = $this.Offset + $length + 1

        return $val
    }

    [byte] ReadNextByte() {
        if (($this.Offset + 1) -gt $this.Buffer.Length) {
            throw [System.IndexOutOfRangeException] "Out of Original Buffer's Boundary"
        }

        $val = $this.Buffer[$this.Offset]
        $this.Offset = $this.Offset + 1
        return $val
    }

    [uint32] ReadNextUInt32LE() {
        if (($this.Offset + 4) -gt $this.Buffer.Length) {
            throw [System.IndexOutOfRangeException] "Out of Original Buffer's Boundary"
        }

        $intBytes = New-Object byte[] 4
        [System.Array]::Copy($this.Buffer, $this.Offset, $intBytes, 0, 4)

        # If the host system runs on big endian architecture, then we're going to have to reverse the byte order of the bytes for this integer
        if (-not([System.BitConverter]::IsLittleEndian)) {
            [Array]::Reverse($intBytes)
        }

        $val = [System.BitConverter]::ToUInt32($intBytes, 0)

        $this.Offset = $this.Offset + 4
        return $val
    }

    [Single] ReadNextFloatLE() {
        if (($this.Offset + 4) -gt $this.Buffer.Length) {
            throw [System.IndexOutOfRangeException] "Out of Original Buffer's Boundary"
        }

        $intBytes = New-Object byte[] 4
        [System.Array]::Copy($this.Buffer, $this.Offset, $intBytes, 0, 4)

        # If the host system runs on big endian architecture, then we're going to have to reverse the byte order of the bytes for this integer
        if (-not([System.BitConverter]::IsLittleEndian)) {
            [Array]::Reverse($intBytes)
        }

        $val = [System.BitConverter]::ToSingle($intBytes, 0)

        $this.Offset = $this.Offset + 4
        return $val
    }

    [UInt64] ReadNextUInt64LE() {
        if (($this.Offset + 8) -gt $this.Buffer.Length) {
            throw [System.IndexOutOfRangeException] "Out of Original Buffer's Boundary"
        }

        $intBytes = New-Object byte[] 8
        [System.Array]::Copy($this.Buffer, $this.Offset, $intBytes, 0, 8)

        # If the host system runs on big endian architecture, then we're going to have to reverse the byte order of the bytes for this integer
        if (-not([System.BitConverter]::IsLittleEndian)) {
            [Array]::Reverse($intBytes)
        }

        $val = [System.BitConverter]::ToUInt64($intBytes, 0)

        $this.Offset = $this.Offset + 8
        return $val
    }
}

function Get-NextMapItem {
    param([BufferReader] $Buffer)

    $typeByte = $Buffer.ReadNextByte()
    if ($typeByte -eq $global:TYPE_MAPEND) {
        return @{
            Type = $typeByte
        }
    }

    $name = $Buffer.ReadNextString([System.Text.Encoding]::GetEncoding('ISO-8859-1'))
    $value;

    switch ($typeByte) {
        $global:TYPE_MAP {
            $value = Get-NextMap -Buffer $Buffer; break
        }
        $global:TYPE_STRING {
            $value = $buffer.ReadNextString([System.Text.Encoding]::UTF8); break;
        }
        $global:TYPE_INT {
            $value = $Buffer.ReadNextUInt32LE(); break;
        }
        $global:TYPE_FLOAT {
            $value = $Buffer.ReadNextFloatLE(); break;
        }
        $global:TYPE_LONG {
            $value = $Buffer.ReadNextUInt64LE(); break;
        }
        default {
            throw [System.InvalidOperationException] "Expected type-signifying byte but got unexpected value '$typeByte'"
        }
    }

    return @{
        Type = $typeByte
        Name = $name
        Value = $value
    }
}

function Get-NextMap {
    param([BufferReader] $Buffer)

    # Use SortedList as map type for alphabetical key sorting and consistently reproducible output, as keys in standard hashtables often tend to be sorted randomly
    $contents = [System.Collections.Generic.SortedList[string, object]]::new()
    # $contents = @{}

    while ($true) {
        $mapItem = Get-NextMapItem -Buffer $Buffer
        if ($mapItem.Type -eq $global:TYPE_MAPEND) {
            break
        }

        $contents[$mapItem.Name] = $mapItem.Value
    }

    return $contents
}

function ConvertFrom-BinaryVDF {
    param(
        [byte[]] $Buffer,
        [int] $Offset = 0
    )

    $reader = [BufferReader]::new($Buffer, $Offset)
    return Get-NextMap($reader)
}
#endregion

#region VDF write functions

function Add-String {
    param(
        [string] $Value,
        [System.Collections.Generic.List[byte]] $Contents,
        [System.Text.Encoding] $Encoding
    )

    $valArr = $Encoding.GetBytes($Value)
    if ([System.Array]::IndexOf($valArr, $global:TYPE_MAP) -ne -1) {
        throw [System.InvalidOperationException] "Strings in VDF files cannot have null chars!"
    }

    $Contents.AddRange($valArr)
    $Contents.Add($global:TYPE_MAP)
}

function Add-Number {
    param(
        $Value,
        [System.Collections.Generic.List[byte]] $Contents
    )

    $valBytes = [System.BitConverter]::GetBytes($Value)
    if (-not([System.BitConverter]::IsLittleEndian)) {
        [array]::Reverse($valBytes)
    }

    $Contents.AddRange($valBytes)
}

function Add-Map {
    param(
        [hashtable] $Map,
        [System.Collections.Generic.List[byte]] $Contents
    )

    foreach ($key in $Map.Keys) {
        $value = $Map[$key]

        switch ($value.GetType().Name) {
            'UInt32' {
                $Contents.Add($global:TYPE_INT)
                Add-String -Value $key -Contents $Contents -Encoding ([System.Text.Encoding]::GetEncoding('ISO-8859-1'))
                Add-Number -Value $value -Contents $Contents
                break
            }
            'UInt64' {
                $Contents.Add($global:TYPE_LONG)
                Add-String -Value $key -Contents $Contents -Encoding ([System.Text.Encoding]::GetEncoding('ISO-8859-1'))
                Add-Number -Value $value -Contents $Contents
                break
            }
            'Single' {
                $Contents.Add($global:TYPE_FLOAT)
                Add-String -Value $key -Contents $Contents -Encoding ([System.Text.Encoding]::GetEncoding('ISO-8859-1'))
                Add-Number -Value $value -Contents $Contents
                break
            }
            'String' {
                $Contents.Add($global:TYPE_STRING)
                Add-String -Value $key -Contents $Contents -Encoding ([System.Text.Encoding]::GetEncoding('ISO-8859-1'))
                Add-String -Value $value -Contents $Contents -Encoding ([System.Text.Encoding]::UTF8)
                break
            }
            'SortedList`2' {
                $Contents.Add($global:TYPE_MAP)
                Add-String -Value $key -Contents $Contents -Encoding ([System.Text.Encoding]::GetEncoding('ISO-8859-1'))
                Add-Map -Map $value -Contents $Contents
                break
            }
            default {
                throw [System.InvalidOperationException] "Type of $key '$($value.GetType().Name)' is not allowed in VDF files. VDF files can only contain strings, unsigned integers, floats, unsigned doubles, and objects"
            }
        }
    }

    $Contents.Add($global:TYPE_MAPEND)
}

function ConvertTo-BinaryVDF {
    [OutputType([byte[]])]
    param([hashtable] $Map)

    $contents = [System.Collections.Generic.List[byte]]::new()

    Add-Map -Map $Map -Contents $contents

    return $contents.ToArray()
}
#endregion

#region shortcuts.vdf manipulation functions

function Add-NonSteamGameShortcut {
    param(
        [Parameter(Mandatory)]
        [ValidateScript({$_.ContainsKey('shortcuts')})]
        [System.Collections.Generic.SortedList[string, object]] $Map,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AppName,

        [Parameter(Mandatory)]
        [ValidateScript({(Test-Path -Path $_ -IsValid)})]
        [string] $ExeLocation,

        [ValidateScript({Test-Path -Path $_ -IsValid})]
        [string] $StartDir = '',

        [ValidateScript({Test-Path -Path $_ -IsValid})]
        [string] $IconLocation = '',

        [ValidateNotNullOrEmpty()]
        [string] $LaunchOptions = '',

        [bool] $IsHidden = $false,

        [bool] $AllowOverlay = $true,

        [bool] $AllowDesktopConfig = $true,

        [bool] $OpenVr = $false
    )

    # 
    [uint32] $appId = Get-Random -Minimum 1000000000 -Maximum ([uint32]::MaxValue - 1)

    if ($Map['shortcuts'].Keys.Count -eq 0) {
        # The first key in shortcuts is always '0'
        $newKey = '0'
    }
    else {
        # New key value will be the last key integer value incremented by 1
        $newKey = [string](([int]($Map['shortcuts'].Keys[-1])) + 1)

        # Check if generated App ID does not conflict with App IDs of existing non-Steam games in shortcuts.vdf
        $existingAppIds = [System.Collections.Generic.List[uint32]]::new()
        foreach ($shortcut in $Map['shortcuts'].GetEnumerator()) {
            if ($shortcut.Value.ContainsKey('appid')) {
                $existingAppIds.Add([uint32]$shortcut.Value['appid'])
            }
        }

        if ($existingAppIds.Count -gt 0) {
            while ($appId -in $existingAppIds) {
                # Keep rerolling until we get a non-conflicting App ID
                [uint32] $appId = Get-Random -Minimum 1000000000 -Maximum ([uint32]::MaxValue - 1)
            }
        }
    }

    # Check if another shortcut with the same AppName exists
    foreach ($shortcut in $Map['shortcuts'].GetEnumerator()) {
        if ($shortcut.Value['AppName'] -eq $AppName) {
            $promptRes = Read-BinaryChoice -Prompt "Found an existing shortcut in shortcuts.vdf that already has the app name '$AppName'. Enter Y to overwrite the existing shortcut or N to add another shortcut with the same app name. [Y/n]" -YesDefault:$true

            if ($promptRes) {
                $newKey = $shortcut.Key
            }

            break
        }
    }

    $newShortcut = [System.Collections.Generic.SortedList[string, object]]::new()
    $newShortcut['AppName'] = $AppName
    $newShortcut['appid'] = $appId
    $newShortcut['exe'] = $ExeLocation
    $newShortcut['StartDir'] = $StartDir
    $newShortcut['icon'] = $IconLocation
    $newShortcut['LaunchOptions'] = $LaunchOptions
    $newShortcut['IsHidden'] = [uint32]$IsHidden 
    $newShortcut['AllowOverlay'] = [uint32]$AllowOverlay 
    $newShortcut['AllowDesktopConfig'] = [uint32]$AllowDesktopConfig
    $newShortcut['openvr'] = [uint32]$OpenVr

    $Map['shortcuts'][$newKey] = $newShortcut

    return $appId
}

#endregion

#endregion

#region Utility functions

function Read-BinaryChoice {
    param(
        [Parameter(Mandatory)] [string] $Prompt,
        [Parameter(Mandatory)] [boolean] $YesDefault
    )

    $yesAnswers = @("yes", "y", "ye", "yeah")
    $noAnswers = @("no", "n", "nah", "nope", "nop")

    do {
        $answer = (Read-Host -Prompt $Prompt).ToLower()

        if (($answer -in $yesAnswers) -or ([string]::IsNullOrEmpty($answer) -and $YesDefault)) {
            return $true
        }

        if (($answer -in $noAnswers) -or ([string]::IsNullOrEmpty($answer) -and -not($YesDefault))) {
            return $false
        }

        Write-Warning "Couldn't parse answer. Try again."
    }
    while ($true)
}

function Read-Choice {
    param(
        [Parameter(Mandatory)] [string] $Prompt,
        [Parameter(Mandatory)] [string[]] $Answers,
        [Parameter(Mandatory)] $DefaultAnswer
    )

    do {
        $answer = (Read-Host -Prompt $Prompt).ToLower()

        if (($answer -in $Answers)) {
            return $answer
        }

        if ([string]::IsNullOrEmpty($answer)) {
            return $DefaultAnswer
        }

        Write-Warning "Couldn't parse answer. Try again."
    }
    while ($true)
}

function Get-TargetFolder {
    Add-Type -AssemblyName System.Windows.Forms 

    $dirSelect = New-Object System.Windows.Forms.FolderBrowserDialog
    $dirSelect.RootFolder = 'UserProfile'
    $dirSelect.Description = "Choose in which folder to install the Sega Model 3 - Supermodel emulator..."
    $dirSelect.ShowNewFolderButton = $true

    do {
        $result = $dirSelect.ShowDialog()
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Warning "Canceled folder selection. Aborting script..."
            exit 1
        }
    
        $validPath = Test-Path $dirSelect.SelectedPath
        if (-not $validPath) {
            Write-Warning "Given path '$targetPath' was not valid or could not be found. Please retry."
        }
    
    } while (-not $validPath)

    return $dirSelect.SelectedPath
}

function Get-LatestSupermodelDownload {
    param(
        [string] $TargetPath
    )

    Write-Information "Checking $BASE_SUPERMODEL_URI for the newest download..."

    $page = Invoke-WebRequest -Method Get -Uri ($BASE_SUPERMODEL_URI + 'Download.html') -UseBasicParsing

    # The link for the newest Windows build should NORMALLY be the first entry in the list of href links of the Download page that contains 'Supermodel_'
    $uriPart = ($page.Links.href | Where-Object {$_ -match 'Supermodel_'})[0]
    if ([string]::IsNullOrEmpty($uriPart)) {
        throw [System.InvalidOperationException] "Could not parse download link of latest Supermodel build at $($BASE_SUPERMODEL_URI + 'Download.html')"
    }

    $downloadUri = $BASE_SUPERMODEL_URI + $uriPart
    $extension = [System.IO.Path]::GetExtension($downloadUri)
    $outputPath = Join-Path $TargetPath ('supermodel' + $extension)

    if (-not($extension -eq '.zip')) {
        throw [System.NotSupportedException] "Latest Supermodel build appears to not be a ZIP file. This script only supports dealing with ZIP files."
    }

    Write-Information "Found newest version at '$downloadUri'. Downloading it to '$outputPath'..."
    Invoke-WebRequest -Method Get -Uri $downloadUri -OutFile $outputPath

    Write-Information "Download complete! Extracting archive..."
    Expand-Archive -LiteralPath $outputPath -DestinationPath $TargetPath -Force

    $romFolder = Join-Path $TargetPath "ROMs"
    if (-not(Test-Path $romFolder)) {
        throw [System.InvalidOperationException] "Expected to find ROM folder at $romFolder, but couldn't find it. Did the archive structure change?"
    }

    Write-Information "Extracted Supermodel archive. Removing archive file..."
    Remove-Item -Path $outputPath -Force
    Write-Information "Successfully deleted archive at '$outputPath'."
}

function Restart-Steam {
    $steamProcess = Get-Process -Name 'Steam'
    $steamPath = $steamProcess.Path

    # Use Steam's own shutdown mechanism for a graceful restart
    Start-Process $steamPath -ArgumentList '-Shutdown' -Wait

    # We need to wait a bit before being able to restart Steam again
    Start-Sleep -Seconds 8
    Start-Process -FilePath $steamPath
}

function New-SpikeOutLaunchOptions {

    do {
        # Add the -throttle option for preventing the emulator from running too fast on displays higher than 60Hz
        $launchOptions = @('-throttle')

        $windowModeSelection = Read-Choice -Answers @(1..3)  -DefaultAnswer '1' -Prompt @"
Which window mode do you want to use for the Supermodel emulator?
1) Fullscreen (default)
2) Windowed
3) Borderless windowed
Enter a number from 1 to 3 to select your option
"@

        switch ($windowModeSelection) {
            '1' { $windowMode = '-fullscreen'; break }
            '2' { $windowMode = '-window'; break }
            '3' { $windowMode = '-borderless'; break}
        }
        $launchOptions += $windowMode

        while ($true) {
            $resolution = Read-Host "`nEnter the desired screen resolution for the Supermodel emulator window separated by a comma (for example: 1920,1080 or 2540,1440 or 1280,720 or 640,480). Leave empty to use the resolution of your current screen" 
            
            if (($resolution -split ',').Count -eq 2) {
                # Remove whitespace in strings in case someone decides to enter it like '1920, 1080'
                $resolution = $resolution.Replace(" ", "")
                $launchOptions += "-res=$resolution"
                break
            }
            elseif ([string]::IsNullOrEmpty($resolution)) {
                break
            } 
            else {
                Write-Information "$resolution did not adhere to expected resolution format 'width,height' (f.e. 640,480). Please try again"
            }
        }

        $useSSAA = Read-Choice -Prompt "`nUse SSAA (supersampling anti-aliasing)? This will reduce jagged edges but is more taxing on your hardware.`nEnter a value from 1 to 8 to set SSAA strength, or enter nothing or 0 to disable SSAA" -Answers @(0..8) -DefaultAnswer '0'
        if ($useSSAA -ne '0') { $launchOptions += "-ss=$useSSAA" } 

        $useWidescreen = Read-BinaryChoice -Prompt "`nDo you want to enable widescreen hacks for SpikeOut?`n(This lets you see more around you, but can cause unimportant graphical glitches during loading screens and stage transitions) [Y/n]" -YesDefault:$true
        if ($useWidescreen) { $launchOptions += '-wide-bg', '-wide-screen' }

        if ([string]::IsNullOrEmpty($resolution)) { $resolutionResult = 'Default' } 
        else { $resolutionResult = $resolution } 

        $confirmPrompt = @"
`nSelected following options:
Window mode: $windowMode
Resolution: $resolutionResult
SSAA: $useSSAA
Widescreen: $($useWidescreen.ToString())

Continue with these options? [Y/n]
"@
        $confirmOptions = Read-BinaryChoice -Prompt $confirmPrompt -YesDefault:$true

    } while (-not $confirmOptions)

    Write-Information "You can always later change these launch options by right-clicking on the Steam shortcuts for SpikeOut and going to Properties... -> Shortcut -> Launch Options."
    return $launchOptions -join ' '
}

function New-WindowsShortcut {
    param(
        [string] $WorkingDirectory,
        [string] $ExeLocation,
        [string] $IcoLocation,
        [string] $ShortcutLocation,
        [string] $LaunchOptions
    )

    $WScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $WScriptShell.CreateShortcut($ShortcutLocation)
    $shortcut.TargetPath = $ExeLocation
    $shortcut.IconLocation = $IcoLocation
    $shortcut.Arguments = $LaunchOptions
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Save()

    Copy-Item -Path $ShortcutLocation -Destination ([IO.Path]::Combine($HOME, "Desktop", (Split-Path $ShortcutLocation -Leaf))) -Force
    Write-Information "Created shortcut at $ShortcutLocation and copied it to desktop."

    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WScriptShell)
}

function Get-Icon {
    param(
        [string] $IconsPath,
        [string] $IconName,
        [string] $IconUri
    )

	if (-not(Test-Path $IconsPath)) {
		$null = New-Item $IconsPath -ItemType Directory
		Write-Information "Created icons folder in Supermodel directory"
	}

	$fullIcoPath = Join-Path $IconsPath $IconName
    Invoke-WebRequest -Method Get -Uri $IconUri -OutFile $fullIcoPath

    return $fullIcoPath
}

#endregion

#region Main functions

function New-RegularShortcuts {
    param(
        [string] $SupermodelPath
    )

    Write-Information "Building Windows shortcuts for SpikeOut: Digital Battle Online and SpikeOut: Final Edition..."

    # Download an optimized standard Supermodel config.
    $configPath = [IO.Path]::Combine($SupermodelPath, 'Config', 'Supermodel.ini')
    Invoke-WebRequest -Method Get -Uri $SUPERMODEL_NONSTEAM_CONFIG_URI -OutFile $configPath
    Write-Information "Replaced Supermodel config file with optimized control setup."

    $romPath = Join-Path $SupermodelPath "ROMs"
    $supermodelExePath = Join-Path $SupermodelPath "Supermodel.exe"
    $launchOptions = New-SpikeOutLaunchOptions

    # The path to the ROM has to be encased in quotes in case the path contains whitespace
    $spikeoutLaunchOptions = "`"$(Join-Path $romPath 'spikeout.zip')`"" + " " + $launchOptions
    $spikeofeLaunchOptions = "`"$(Join-Path $romPath 'spikeofe.zip')`"" + " " + $launchOptions

	# Download icons to a new icons folder in the Supermodel directory
	$icoDirPath = Join-Path $SupermodelPath "Icons"
    $spikeoutIcoPath = Get-Icon -IconsPath $icoDirPath -IconName "spikeout.ico" -IconUri $SPIKEOUT_ICO_URI
    $spikeofeIcoPath = Get-Icon -IconsPath $icoDirPath -IconName "spikeofe.ico" -IconUri $SPIKEOFE_ICO_URI

    New-WindowsShortcut -WorkingDirectory $SupermodelPath -ExeLocation $supermodelExePath -IcoLocation $spikeoutIcoPath -LaunchOptions $spikeoutLaunchOptions -ShortcutLocation (Join-Path $SupermodelPath "SpikeOut Digital Battle Online.lnk")
    New-WindowsShortcut -WorkingDirectory $SupermodelPath -ExeLocation $supermodelExePath -IcoLocation $spikeofeIcoPath -LaunchOptions $spikeofeLaunchOptions -ShortcutLocation (Join-Path $SupermodelPath "SpikeOut Final Edition.lnk")

    Write-Information "Operation successful! Remember that you can always change the Supermodel options by editing the launch options in the SpikeOut shortcut properties."
}

function New-SteamShortcuts {
    param(
        [string] $SupermodelPath
    )

    # Steam must be running so that we can read the ID of the current active Steam user in the registry
    do {

        $isSteamRunning = -not((Get-ItemPropertyValue "HKCU:\SOFTWARE\Valve\Steam\ActiveProcess" -Name ActiveUser -ErrorAction SilentlyContinue) -in @(0, $null))

        if (-not $isSteamRunning) {
            $null = Read-Host -Prompt "Could not detect that an instance of Steam was running on this system. Please launch Steam then press ENTER on this screen to try again"
        }
    } while (-not $isSteamRunning)

    # Download the Supermodel config tuned for use with Steam Input. This one has joystick binds removed from the native Supermodel config, so that it won't interfere with the Steam Input config.
    $configPath = [IO.Path]::Combine($SupermodelPath, 'Config', 'Supermodel.ini')
    Invoke-WebRequest -Method Get -Uri $SUPERMODEL_STEAM_CONFIG_URI -OutFile $configPath
    Write-Information "Replaced Supermodel config file with keybind setup for use with Steam Input. Make sure you don't change the binds without also changing them in the Steam Controller Configs for SpikeOut too, otherwise it might break."

    # Read Steam path and current user ID from registry
    $steamPath = Get-ItemPropertyValue "HKCU:\SOFTWARE\Valve\Steam" -Name SteamPath
    $steamUserId = Get-ItemPropertyValue "HKCU:\SOFTWARE\Valve\Steam\ActiveProcess" -Name ActiveUser

    $shortcutsPath = [IO.Path]::Combine($steamPath, "userdata", $steamUserId, "config", "shortcuts.vdf")
    $controllerConfigPath = [IO.Path]::Combine($steamPath, "steamapps", "common", "Steam Controller Configs", $steamUserId, "config")

    if (-not (Test-Path (Split-Path $shortcutsPath -Parent))) {
        Write-Warning "Path to shortcuts.vdf ($shortcutsPath) wasn't valid. Make sure Steam is active and running before running this script"
        exit 1
    }

    if (-not (Test-Path $shortcutsPath)) {
        Write-Information "shortcuts.vdf not yet made in Steam userdata config. Creating a new default shortcuts file..."

        # As we're dealing with a binary file, we have to initialize a default file with a byte array. This basically translates to a VDF file with one key named 'shortcuts' and an empty object value
        $defaultShortcutsValue = [byte[]] @(0, 115, 104, 111, 114, 116, 99, 117, 116, 115, 0, 8, 8)
        $null = New-Item -Path $shortcutsPath -ItemType File
        [IO.File]::WriteAllBytes($shortcutsPath, $defaultShortcutsValue)
    }

    # Create backup of shortcuts.vdf just in case
    $shortcutsBackupName = "shortcuts_backup_$(Get-Date -Format "MMddyyyy-HHmmss").vdf"
    $shortcutBackupPath = Join-Path (Split-Path $shortcutsPath -Parent) $shortcutsBackupName
    Copy-Item -Path $shortcutsPath -Destination $shortcutBackupPath -Force
    Write-Information "Created backup of shortcuts.vdf at $shortcutBackupPath"

    # Import shortcuts.vdf
    $shortcutMap = ConvertFrom-BinaryVDF -Buffer ([System.IO.File]::ReadAllBytes($shortcutsPath))
    Write-Information "Successfully imported shortcuts.vdf. Adding shortcuts..."

    # Construct the shortcut options
    $romPath = Join-Path $SupermodelPath "ROMs"
    $supermodelExePath = Join-Path $SupermodelPath "Supermodel.exe"
    $launchOptions = New-SpikeOutLaunchOptions

    # The path to the ROM has to be encased in quotes in case the path contains whitespace
    $spikeoutLaunchOptions = "`"$(Join-Path $romPath 'spikeout.zip')`"" + " " + $launchOptions
    $spikeofeLaunchOptions = "`"$(Join-Path $romPath 'spikeofe.zip')`"" + " " + $launchOptions

	# Download icons to a new icons folder in the Supermodel directory
	$icoDirPath = Join-Path $SupermodelPath "Icons"
    $spikeoutIcoPath = Get-Icon -IconsPath $icoDirPath -IconName "spikeout.ico" -IconUri $SPIKEOUT_ICO_URI
    $spikeofeIcoPath = Get-Icon -IconsPath $icoDirPath -IconName "spikeofe.ico" -IconUri $SPIKEOFE_ICO_URI

    # Add the new SpikeOut shortcuts to the shortcuts map
    $null = Add-NonSteamGameShortcut -Map $shortcutMap -AppName 'SpikeOut: Digital Battle Online' -ExeLocation $supermodelExePath -StartDir $SupermodelPath -LaunchOptions $spikeoutLaunchOptions -IconLocation $spikeoutIcoPath -AllowOverlay:$true -AllowDesktopConfig:$true
    $null = Add-NonSteamGameShortcut -Map $shortcutMap -AppName 'SpikeOut: Final Edition' -ExeLocation $supermodelExePath -StartDir $SupermodelPath -LaunchOptions $spikeofeLaunchOptions -IconLocation $spikeofeIcoPath -AllowOverlay:$true -AllowDesktopConfig:$true

    # Export changes to shortcuts.vdf
    [System.IO.File]::WriteAllBytes($shortcutsPath, (ConvertTo-BinaryVDF $shortcutMap))
    Write-Information "Successfully added non-Steam game shortcuts for SpikeOut: Digital Battle Online and SpikeOut: Final Edition to your Steam Library."

    # Download the Steam Input config for SpikeOut and place them in the necessary folders
    $configDownloadDest = Join-Path $env:TEMP 'supermodel - spikeout gamepad (powershell setup)_0.vdf'
    Invoke-WebRequest -Method Get -Uri $SPIKEOUT_STEAM_INPUT_CONFIG_URI -OutFile $configDownloadDest

    $spikeoutControllerConfigPath = Join-Path $controllerConfigPath 'spikeout digital battle online'
    $spikeofeControllerConfigPath = Join-Path $controllerConfigPath 'spikeout final edition'

    # Create folders for the Steam controller configs if they don't exist yet
    if (-not (Test-Path $spikeoutControllerConfigPath)) {
        $null = New-Item -Path $controllerConfigPath -Name 'spikeout digital battle online' -ItemType Directory
        Write-Information "Added controller config folder for SpikeOut: Digital Battle Online..."
    }

    if (-not (Test-Path $spikeofeControllerConfigPath)) {
        $null = New-Item -Path $controllerConfigPath -Name 'spikeout final edition' -ItemType Directory
        Write-Information "Added controller config folder for SpikeOut: Final Edition..."
    }

    Copy-Item -Path $configDownloadDest -Destination $spikeoutControllerConfigPath -Force
    Copy-Item -Path $configDownloadDest -Destination $spikeofeControllerConfigPath -Force

    Write-Information "Successfully copied SpikeOut controller configs to the controller config folder!"

    # Prompt user to restart Steam
    $cont = Read-BinaryChoice -Prompt "Steam must be restarted for the new shortcuts to appear in your library. Restart Steam now? [Y/n]" -YesDefault:$true
    if ($cont) { Restart-Steam }

    # Show user the Steam control setup for SpikeOut
    Write-Information "Opening an image in your browser on the SpikeOut control scheme..."
    Start-Process $SPIKEOUT_CONTROLS_URI

    Write-Warning @"
The SpikeOut shortcuts should be working fine now, but you will have to manually enable Steam Input for the new shortcuts to have the SpikeOut controller config take effect. To do so:

1. On either of the new SpikeOut shortcuts in your Steam Library (these only show up after you restarted Steam), click the Properties button in the pop-up menu.
2. Go to the Controller tab, then change the "Override for SpikeOut: Final Edition / Digital Battle Online" option from "Use default settings" to "Enable Steam Input"

After that, the custom provided SpikeOut controller config should be automatically applied when you start the game!

NOTE: You are going to have to find the SpikeOut ROMs (spikeout.zip and spikeofe.zip) yourself and place them in the ROMs directory of whereever you installed Supermodel ($romPath) to be able to play the games.
Make sure you get a NON-MERGED ROM set. MERGED ROM sets will NOT work.
"@
}

function Main {
    try {
        Write-Information "Starting Supermodel (Windows) + SpikeOut: Digital Battle Online / Final Edition installer by testament_enjoyment..."

        # Abort script if ran on non-Windows system
        if (-not($Env:OS -match 'Windows')) {
            Write-Warning "This script is designed to only work on Windows."
            exit 1
        }

        # Build open file dialog to pick the Supermodel emulator folder
        $selectedPath = Get-TargetFolder
        
        # Prompt user to download Supermodel emulator
        $cont = Read-BinaryChoice -Prompt "Download the SEGA Model 3 Supermodel emulator to '$selectedPath'?`n(RECOMMENDED, this is required to be able to play SpikeOut at all. Enter N(o) only if you already have Supermodel downloaded) [Y/n]" -YesDefault:$true
        if ($cont) {
            Get-LatestSupermodelDownload -TargetPath $selectedPath
        }
        else {
            if (-not(Test-Path -Path (Join-Path $selectedPath "Supermodel.exe"))) {
                Write-Warning "Rejected download, but could not find existing Supermodel installation at location '$selectedPath'. Aborting script..."
                exit 1
            }
        }

        # Check if Steam is installed on this system
        $isSteamInstalled = $null -ne (Get-ItemPropertyValue "HKCU:\SOFTWARE\Valve\Steam" -Name SteamPath -ErrorAction SilentlyContinue)
        if (-not $isSteamInstalled) {
            Write-Information "Could not find Steam installation on current system..."
        }

        # Automatically create standard Windows shortcuts and exit script if no Steam installation found 
        if (-not $isSteamInstalled) {
            New-RegularShortcuts -SupermodelPath $selectedPath
            exit 0
        }

        $cont = Read-Choice -Answers @(1, 2) -DefaultAnswer '1' -Prompt @"
Select how you want to create your SpikeOut shortcuts:
1) (RECOMMENDED) Create shortcuts for SpikeOut in your Steam library. This also sets up a custom Steam Input config with some useful macros, that are also likely to work on all types of controllers.
2) Create standard Windows shortcuts. Uses XInput as an input system, and certain macros (pausing the emulator, savestate control, and a macro for special attacks) won't be available on your controller.

Enter a number (1, 2) to select your option
"@
        switch ($cont) {
            '1' { New-SteamShortcuts -SupermodelPath $selectedPath; break }
            '2' { New-RegularShortcuts -SupermodelPath $selectedPath; break }
        }
    }
    catch {
        $err = [PSCustomObject]@{
            ErrorMessage = $_.Exception.Message
            ExceptionType = $_.Exception.GetType()
            Base = $_.InvocationInfo.PositionMessage
            StackTrace = $_.ScriptStackTrace
        }

        $err | Format-List
        Write-Warning "FATAL ERROR. Terminating script..."

        exit 1
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
}

#endregion

Main

# To run this script remotely, open a PowerShell window and copypaste the following command:
# Invoke-RestMethod -Method Get 'https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/main/Setup-SpikeOut/Setup-SpikeOut.ps1' | Invoke-Expression

# If you're running this on a PowerShell version higher than 5.X, then you have to change the ExecutionPolicy first by running the following command:
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser