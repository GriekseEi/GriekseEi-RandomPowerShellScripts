<#
    .SYNOPSIS
        Downloads the latest Supermodel emulator build for Windows, and sets it up to be able to play both versions of SpikeOut.
    .DESCRIPTION
        
#>

#region Global Variables
$InformationPreference = 'Continue'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Add-Type -AssemblyName System.Windows.Forms

$BASE_SUPERMODEL_URI = 'https://supermodel3.com/'
$SUPERMODEL_CONFIG_URI = ''

# 'https://drive.google.com/file/d/1lzkgH6_7wvkPzwmgJdmuj3y4vNh1cZ9k/view?usp=sharing'
# 'https://drive.google.com/file/d/1ex8whPwJeOemeVYCKa5UwiZm9DEHT2lh/view?usp=sharing'
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

    [uint] ReadNextUInt32LE() {
        if (($this.Offset + 4) -gt $this.Buffer.Length) {
            throw [System.IndexOutOfRangeException] "Out of Original Buffer's Boundary"
        }

        $intBytes = New-Object byte[] 4
        [System.Array]::Copy($this.Buffer, $this.Offset, $intBytes, 0, 4)

        # If the host system runs on big endian architecture, then we're going to have to reverse the byte order of the bytes for this integer
        if (-not([System.BitConverter]::IsLittleEndian)) {
            [Array]::Reverse($intBytes)
        }

        $val = [System.BitConverter]::ToUInt32($intBytes)

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

        $val = [System.BitConverter]::ToSingle($intBytes)

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

        $val = [System.BitConverter]::ToUInt64($intBytes)

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
    [OutputType([hashtable])]
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
    [uint] $appId = Get-Random -Minimum 1000000000 -Maximum ([uint]::MaxValue - 1)

    if ($Map['shortcuts'].Keys.Count -eq 0) {
        # The first key in shortcuts is always '0'
        $newKey = '0'
    }
    else {
        # New key value will be the last key integer value incremented by 1
        $newKey = [string](([int]($Map['shortcuts'].Keys[-1])) + 1)

        # Check if generated App ID does not conflict with App IDs of existing non-Steam games in shortcuts.vdf
        $existingAppIds = [System.Collections.Generic.List[uint]]::new()
        foreach ($shortcut in $Map['shortcuts'].GetEnumerator()) {
            if ($shortcut.Value.ContainsKey('appid')) {
                $existingAppIds.Add([uint]$shortcut.Value['appid'])
            }
        }

        if ($existingAppIds.Count -gt 0) {
            while ($appId -in $existingAppIds) {
                # Keep rerolling until we get a non-conflicting App ID
                [uint] $appId = Get-Random -Minimum 1000000000 -Maximum ([uint]::MaxValue - 1)
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
    $newShortcut['IsHidden'] = [uint]$IsHidden 
    $newShortcut['AllowOverlay'] = [uint]$AllowOverlay 
    $newShortcut['AllowDesktopConfig'] = [uint]$AllowDesktopConfig
    $newShortcut['openvr'] = [uint]$OpenVr

    $Map['shortcuts'][$newKey] = $newShortcut

    return $appId
}

#endregion

#endregion

#region Main functions
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

    # TODO: Uncomment me
    $configPath = Join-Path $TargetPath 'Config' | Join-Path -ChildPath 'Supermodel.ini'
    Copy-Item -Path '/home/durandal/Scripts/Powershell/GriekseEi-RandomPowerShellScripts/Setup-SpikeOut/resources/Supermodel.ini' -Destination $configPath -Force 
    # Write-Information "Replacing Supermodel config file with adjusted config file from '$SUPERMODEL_CONFIG_URI' and downloading it to '$configPath'..."
    # Invoke-WebRequest -Method Get -Uri $SUPERMODEL_CONFIG_URI -OutFile $configPath
    Write-Information "Successfully updated Supermodel config file!"

}

function Build-SpikeOutLaunchOptions {

    while ($true) {
        # Add the -throttle option for preventing the emulator from running too fast on displays higher than 60Hz
        $launchOptions = @('-throttle')

        $windowModeSelection = Read-Choice -Prompt "Which window mode do you want to use for the Supermodel emulator? Enter the number of the corresponding option:`n1) Fullscreen (default)`n2) Windowed`n3) Borderless windowed" -Answers @(1..3)  -DefaultAnswer '1'
        switch ($windowModeSelection) {
            '1' { $windowMode = '-fullscreen'; break }
            '2' { $windowMode = '-window'; break }
            '3' { $windowMode = '-borderless'; break}
        }
        $launchOptions += $windowMode

        while ($true) {
            $resolution = Read-Host "Enter the desired screen resolution for the Supermodel emulator window separated by a comma (for example: 1920,1080 or 2540,1440 or 1280,720 or 640,480). Leave empty to use the resolution of your current screen" 
            
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

        $useSSAA = Read-Choice -Prompt "Use SSAA (supersampling anti-aliasing)? This will reduce jagged edges but is more taxing on your hardware. Enter a value from 1 to 8 to set SSAA strength, or enter nothing or 0 to disable SSAA" -Answers @(0..8) -DefaultAnswer '0'
        if ($useSSAA -ne '0') {
            $launchOptions += "-ss $useSSAA"
        } 

        $useWidescreen = Read-BinaryChoice -Prompt "Do you want to enable widescreen hacks for SpikeOut? This lets you see more around you, but will cause unimportant graphical glitches during loading screens and stage transitions. [Y/n]" -YesDefault:$true
        if ($useWidescreen) {
            $launchOptions += '-wide-bg', '-wide-screen'
        }

        if ([string]::IsNullOrEmpty($resolution)) { 
            $resolutionResult = 'Default' 
        } 
        else { 
            $resolutionResult = $resolution 
        } 


        $confirmPrompt = @"
Selected following options:
Window mode: $windowMode
Resolution: $resolutionResult
SSAA: $useSSAA
Widescreen: $($useWidescreen.ToString())

Continue with these options? [Y/n]
"@
        $confirmOptions = Read-BinaryChoice -Prompt $confirmPrompt -YesDefault:$true

        if ($confirmOptions) {
            break
        }
    }

    Write-Information "You can always later change these launch options by right-clicking on the Steam shortcuts for SpikeOut and going to Properties... -> Shortcut -> Launch Options."
    return $launchOptions -join ' '
}


function Enable-SteamInputForSpikeOut {
    param(
        [uint] $SpikeoutId,
        [uint] $SpikeofeId
    )

    # TODO: Un-hardcode this
    $localconfigPath = "/home/durandal/.steam/steam/userdata/70715094/config/localconfig.vdf"

    # Create backup of localconfig just in case
    Write-Information "Creating backup of localconfig.vdf..."
    $backupName = "localconfig_backup_$(Get-Date -Format "MMddyyyy-HHmmss").vdf"
    $backupPath = Join-Path (Split-Path -Path $localconfigPath -Parent) $backupName
    Copy-Item -Path $localconfigPath -Destination $backupPath -Force
    Write-Information "Successfully made a backup at $backupPath"

    $importedVdf = Get-Content -Path $localconfigPath -Raw

    $entrypoint = 
@"
	}
	"apps"
	{
"@

    if (([regex]::Matches($importedVdf, $entrypoint).Count -ne 1)) {
        Write-Warning @"
Could not find a proper entrypoint in your localconfig.vdf to automatically enable Steam Input and the custom controller configs for the new SpikeOut shortcuts. 
The SpikeOut shortcuts should be working fine now, but you will have to manually enable Steam Input for the new shortcuts to have the SpikeOut controller config take effect. To do so:

1. Restart your Steam client (the new SpikeOut shortcuts won't show up until you do)
2. On either of the new SpikeOut shortcuts in your Steam Library, click the Properties button in the pop-up menu.
3. Go to the Controller tab, then change the "Override for SpikeOut: Final Edition / Digital Battle Online" option from "Use default settings" to "Enable Steam Input"

After that, the custom provided SpikeOut controller config should be automatically applied when you start the game!

NOTE: You are going to have to find the SpikeOut ROMs (spikeout.zip and spikeofe.zip) yourself and place them in the ROMs directory of whereever you installed Supermodel to be able to play the games.
"@
        exit 0
    }

    # For some reason, the app ID keys for the controller config sections of non-steam games is stored as (appId - uint max value - 1), meaning it's always a negative number 
    $adjustedSpikeoutId = $SpikeoutId - [uint]::MaxValue - 1
    $adjustedSpikeofeId = $SpikeofeId - [uint]::MaxValue - 1

    # SUUUUUUUUUUUUUUPER hacky way of doing this, but screw it
$endResult = 
@"
	}
	"apps"
	{
		"$adjustedSpikeoutId"
		{
			"UseSteamControllerConfig"		"2"
			"SteamControllerRumble"		"-1"
			"SteamControllerRumbleIntensity"		"320"
		}
		"$adjustedSpikeofeId"
		{
			"UseSteamControllerConfig		"2"
			"SteamControllerRumble"		"-1"
			"SteamControllerRumbleIntensity"		"320"
		}
"@

    $importedVdf = $importedVdf.Replace($entrypoint, $endResult)

    [System.IO.File]::WriteAllText($localconfigPath, $importedVdf)
    Write-Information "Custom Steam controller configs for SpikeOut should now be enabled!"
}

function New-SteamShortcuts {
    param(
        [string] $SupermodelPath
    )

    $shortcutsPath = '/home/durandal/.steam/steam/userdata/70715094/config/shortcuts.vdf'
    # while ($true) {
    #     $shortcutsPath = Read-Host "Enter the full filepath for where the shortcuts.vdf file is located. This is usually located at C:/Program Files (x86)/Steam/userdata/<your-user-id>/config/shortcuts.vdf"

    #     if (-not(Test-Path $shortcutsPath)) {
    #         Write-Information "Given file path for shortcuts.vdf was not valid. Please try again"
    #     }
    #     elseif (-not($shortcutsPath.EndsWith('.vdf'))) {
    #         Write-Information "Given file path did not select a .vdf file. Please try again"
    #     }
    #     else {
    #         break
    #     }
    # }

    # Create backup of shortcuts.vdf just in case
    $shortcutsBackupName = "shortcuts_backup_$(Get-Date -Format "MMddyyyy-HHmmss").vdf"
    $shortcutBackupPath = Join-Path (Split-Path $shortcutsPath -Parent) $shortcutsBackupName
    Copy-Item -Path $shortcutsPath -Destination $shortcutBackupPath -Force
    Write-Information "Created backup of shortcuts.vdf at $shortcutBackupPath"

    # Import shortcuts.vdf
    $shortcutMap = ConvertFrom-BinaryVDF -Buffer ([System.IO.File]::ReadAllBytes($shortcutsPath))
    Write-Information "Successfully imported shortcuts.vdf. Adding shortcuts..."

    # Construct the shortcut / launch options
    $romPath = Join-Path $SupermodelPath "ROMs"
    $supermodelExePath = Join-Path $SupermodelPath "Supermodel.exe"
    $launchOptions = Build-SpikeOutLaunchOptions

    $spikeoutLaunchOptions = "`"$(Join-Path $romPath 'spikeout.zip')`"" + " " + $launchOptions
    $spikeofeLaunchOptions = "`"$(Join-Path $romPath 'spikeofe.zip')`"" + " " + $launchOptions

	# Download icons
	$icoDirPath = Join-Path $SupermodelPath "Icons"
	if (-not(Test-Path $icoDirPath)) {
		New-Item $icoDirPath -ItemType Directory
		Write-Information "Created icons folder in Supermodel directory"
	}

	# TODO: Replace this with actual download logic to new icons folder
	$spikeoutIcoPath = "/home/durandal/Scripts/Powershell/GriekseEi-RandomPowerShellScripts/Setup-SpikeOut/resources/spikeout.ico"
	$spikeofeIcoPath = "/home/durandal/Scripts/Powershell/GriekseEi-RandomPowerShellScripts/Setup-SpikeOut/resources/spikeofe.ico"

    # Add the new SpikeOut shortcuts to the shortcuts map
    $spikeoutAppId = Add-NonSteamGameShortcut -Map $shortcutMap -AppName 'SpikeOut: Digital Battle Online' -ExeLocation $supermodelExePath -StartDir $SupermodelPath -LaunchOptions $spikeoutLaunchOptions -IconLocation $spikeoutIcoPath -AllowOverlay:$true -AllowDesktopConfig:$true
    $spikeofeAppId = Add-NonSteamGameShortcut -Map $shortcutMap -AppName 'SpikeOut: Final Edition' -ExeLocation $supermodelExePath -StartDir $SupermodelPath -LaunchOptions $spikeofeLaunchOptions -IconLocation $spikeofeIcoPath -AllowOverlay:$true -AllowDesktopConfig:$true

    # TODO: remove this shit
    Write-Information $spikeoutAppId
    Write-Information $spikeofeAppId

    # Export changes to shortcuts.vdf
    [System.IO.File]::WriteAllBytes($shortcutsPath, (ConvertTo-BinaryVDF $shortcutMap))
    Write-Information "Successfully added non-Steam game shortcuts for SpikeOut: Digital Battle Online and SpikeOut: Final Edition to your Steam Library."

    # TODO: Don't hardcode this
    $controllerConfigPath = '/home/durandal/.steam/steam/steamapps/common/Steam Controller Configs/70715094/config/'
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

    # Copy the Steam controller configs to the game-specific controller config folders
    # TODO: These files should be downloaded from a git repo
	$controllerVdf = '/home/durandal/Scripts/Powershell/GriekseEi-RandomPowerShellScripts/Setup-SpikeOut/resources/supermodel - spikeout gamepad (powershell setup)_0.vdf'

    Copy-Item -Path $controllerVdf -Destination $spikeoutControllerConfigPath -Force
    Copy-Item -Path $controllerVdf -Destination $spikeofeControllerConfigPath -Force

    Write-Information "Successfully copied SpikeOut controller configs to the controller config folder!"

    # Enable-SteamInputForSpikeOut -SpikeoutId $spikeoutAppId -SpikeofeId $spikeofeAppId
}
#endregion

function Main {
    try {
        Write-Information "Starting Supermodel (Windows) + SpikeOut installer by testament_enjoyment..."

        if (-not($PSVersionTable.Platform -match 'Windows')) {
            $res = Read-BinaryChoice -Prompt "This script will download the Windows version of Supermodel and therefore might not work on your platform. Continue regardless? [y/N]" -YesDefault:$false
            if (-not $res) {
                exit 0
            }
        }
    
        do {
            $targetPath = Read-Host "Enter the full filepath for where you want to download the Supermodel emulator (Press ENTER or leave empty to use the current directory)"
        
            if ([string]::IsNullOrEmpty($targetPath)) {
                $targetPath = $PSScriptRoot
            }
            else {
                $targetPath = Resolve-Path $targetPath
            }
        
            $validPath = Test-Path $targetPath
            if (-not $validPath) {
                Write-Warning "Given path '$targetPath' was not valid or could not be found. Please retry."
            }
        
        } while (-not $validPath)

        
        $cont = Read-BinaryChoice -Prompt "Download the Supermodel emulator to '$targetPath'? [Y/n]" -YesDefault:$true
        if ($cont) {
            Get-LatestSupermodelDownload -TargetPath $targetPath
        }

        $cont = Read-BinaryChoice -Prompt "Add shortcuts for SpikeOut: Digital Battle Online and Final Edition to your Steam library? (Recommended, as this will also set up all the input bindings for SpikeOut using Steam Input to work out-of-the-box. Note that Steam does have to already be installed and setup on your system) [Y/n]" -YesDefault:$true
        if ($cont) {
            New-SteamShortcuts -SupermodelPath $targetPath
        }
        
        Write-Warning @"
The SpikeOut shortcuts should be working fine now, but you will have to manually enable Steam Input for the new shortcuts to have the SpikeOut controller config take effect. To do so:

1. Restart your Steam client (the new SpikeOut shortcuts won't show up until you do)
2. On either of the new SpikeOut shortcuts in your Steam Library, click the Properties button in the pop-up menu.
3. Go to the Controller tab, then change the "Override for SpikeOut: Final Edition / Digital Battle Online" option from "Use default settings" to "Enable Steam Input"

After that, the custom provided SpikeOut controller config should be automatically applied when you start the game!

NOTE: You are going to have to find the SpikeOut ROMs (spikeout.zip and spikeofe.zip) yourself and place them in the ROMs directory of whereever you installed Supermodel ($(Join-Path $targetPath "ROMs")) to be able to play the games.
"@
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
}

Main


