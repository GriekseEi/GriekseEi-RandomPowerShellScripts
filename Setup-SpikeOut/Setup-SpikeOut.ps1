#requires -Version 5.0

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
        - Designed to work with the default PowerShell installation on most Windows systems (PS 5.1) for total out-of-the-box compatibility.

        - This script does not supply the SpikeOut ROMs. For legal reasons these have to be found yourself and placed in the ROMs directory of
        the Supermodel folder.

        - The Steam Input version of the Supermodel.ini config has all relevant joystick inputs scrubbed to avoid issues related to both
        Supermodel and Steam Input firing the same input simultaneously, which *may* cause issues.

        Author: testament_enjoyment
    .LINK
        https://supermodel3.com/ - Homepage of Supermodel
    .LINK
        https://developer.valvesoftware.com/wiki/VDF - Official documentation on the Steam VDF format
    .LINK
        https://developer.valvesoftware.com/wiki/Binary_VDF - Official documentation on the Steam Binary VDF format
#>

#region Global Variables

$oldErrorActionPreference = $ErrorActionPreference

$InformationPreference = 'Continue'
$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$SCRIPT_VERSION = [version]'1.0.3'

# URLs for various resources we need to download
$CurrentBranch = 'main'  # This is only really used for debugging and testing
$BASE_SUPERMODEL_URI = 'https://supermodel3.com/'
$SUPERMODEL_STEAM_CONFIG_URI = "https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/$CurrentBranch/Setup-SpikeOut/resources/steamconfig/Supermodel.ini"
$SUPERMODEL_NONSTEAM_GAMEPAD_CONFIG_URI = "https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/$CurrentBranch/Setup-SpikeOut/resources/nonsteamconfig_gamepad/Supermodel.ini"
$SUPERMODEL_NONSTEAM_FIGHTSTICK_CONFIG_URI = "https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/$CurrentBranch/Setup-SpikeOut/resources/nonsteamconfig_fightstick/Supermodel.ini"
$SPIKEOUT_STEAM_INPUT_CONFIG_GAMEPAD_URI = "https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/$CurrentBranch/Setup-SpikeOut/resources/supermodel%20-%20spikeout%20gamepad%20(powershell%20setup)_0.vdf"
$SPIKEOUT_STEAM_INPUT_CONFIG_FIGHTSTICK_URI = "https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/$CurrentBranch/Setup-SpikeOut/resources/supermodel%20-%20spikeout%20fightstickarcade%20stick%20(powershell%20setup)_0.vdf"
$SPIKEOUT_ICO_URI = "https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/$CurrentBranch/Setup-SpikeOut/resources/spikeout.ico"
$SPIKEOFE_ICO_URI = "https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/$CurrentBranch/Setup-SpikeOut/resources/spikeofe.ico"
$SPIKEOUT_GAMEPAD_CONTROLS_URI = "https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/$CurrentBranch/Setup-SpikeOut/resources/spikeout_controls_howto_gamepad.webp"
$SPIKEOUT_FIGHTSTICK_CONTROLS_URI = "https://raw.githubusercontent.com/GriekseEi/GriekseEi-RandomPowerShellScripts/refs/heads/$CurrentBranch/Setup-SpikeOut/resources/spikeout_controls_howto_fightstick.webp"
$GAMEPAD_CONFIG_NAME = "supermodel - spikeout gamepad (powershell setup)_0"
$FIGHTSTICK_CONFIG_NAME = "supermodel - spikeout fightstickarcade stick (powershell setup)_0"
$TURBO_MODE_FRAMERATE = 69.0288

# We're leaving the Steam Deck configset ('neptune') out of this since it's unlikely anybody is running Windows and this script on one, also so it possibly doesn't override EmuDeck configurations
$CONTROLLER_TYPES = @('ps4', 'ps5', 'ps5_edge', 'xboxelite', 'xboxone', 'xbox360', 'switch_pro', 'steamcontroller_gordon', 'generic')

# Values of the type bytes used in binary VDFs to signify the type of the next value. See the Binary VDF documentation
$script:TYPE_MAP = [byte] 0
$script:TYPE_STRING = [byte] 1
$script:TYPE_INT = [byte] 2
$script:TYPE_FLOAT = [byte] 3
$script:TYPE_LONG = [byte] 7
$script:TYPE_MAPEND = [byte] 8

#endregion

#region VDF functions

function ConvertFrom-VDF {
    <#
        .SYNOPSIS
            Converts a Steam VDF (KeyValues) text file to an ordered hashtable
        .PARAMETER InputObject
            A string array of all lines in a VDF file
        .PARAMETER CurrentLine
            A ref counter for keeping track of what depth level of the VDF we're currently in. Only used for when this function is called recursively
        .PARAMETER RegExCompare
            The regex for capturing the key, value, and brace symbols of the current line
        .OUTPUTS
            [OrderedDictionary] - The input VDF parsed as an ordered hashtable
        .EXAMPLE
            PS> $vdf = ConvertFrom-VDF ([IO.File]::ReadAllLines('./test.vdf'))
        .NOTES
            Original code and regex by u/SMFX
            Source: https://www.reddit.com/r/PowerShell/comments/egosaf/comment/fcambsr/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
        .LINK
            https://developer.valvesoftware.com/wiki/VDF
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ $_.Count -gt 0 })]
        [string[]] $InputObject,

        [ref] $CurrentLine = ([ref]0),

        [ValidateNotNullOrEmpty()]
        [string] $RegExCompare = '\A\s*((?<Key>"[^"]+")|(?<Brace>[\{\}]))\s*(?<LineValue>"[^"]*")?\Z'
    )

    $currTable = [ordered]@{}

    while ($currentLine.Value -lt $InputObject.Count) {
        if ($InputObject[$currentLine.Value] -match $RegExCompare) {
            if ($matches.Key) {
                $currKey = $matches.Key
            }

            # Call function recursively for each object we encounter (as signified by an opening curly brace) until we hit a closing curly brace
            if ($matches.LineValue) {
                $currTable.$currKey = $matches.LineValue
            } elseif ($matches.Brace -eq '{') {
                $currentLine.Value++
                $currTable.$currKey = ConvertFrom-VDF -InputObject $InputObject -CurrentLine $CurrentLine -RegExCompare $RegExCompare
            } elseif ($matches.Brace -eq '}') {
                break
            }
        } else {
            throw [System.Data.SyntaxErrorException] "Error while parsing VDF: Could not capture either key or value at line $($CurrentLine.Value)"
        }

        $currentLine.Value++
    }

    return $currTable
}

function ConvertTo-VDF {
    <#
        .SYNOPSIS
            Convert an ordered hashtable to the Steam VDF format
        .PARAMETER InputObject
            The ordered hashtable to convert to a VDF string
        .PARAMETER Depth
            A ref counter for keeping track of what depth level of the VDF we're currently in. Only used for when this function is called recursively
        .OUTPUTS
            [string] - A string representation of a VDF object
        .LINK
            https://developer.valvesoftware.com/wiki/VDF
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ $_.Count -gt 0 })]
        [System.Collections.Specialized.OrderedDictionary] $InputObject,

        [ref] $Depth = ([ref]0)
    )

    $root = [System.Collections.Generic.List[string]]::new()
    # Indent new values accordingly depending on their depth level
    $tabs = "`t" * $Depth.Value

    foreach ($entry in $InputObject.GetEnumerator()) {
        if ($entry.Value.GetType() -eq [System.Collections.Specialized.OrderedDictionary]) {
            # Keys and curly braces have each to be on their own lines
            $Depth.Value++
            $root.Add($tabs + $entry.Key)
            $root.Add($tabs + '{')
            $root.AddRange((ConvertTo-VDF -InputObject $entry.Value -Depth $Depth))
            $root.Add($tabs + '}')
            $Depth.Value--
        } else {
            # There's always two tabs between a key and a value
            $root.Add($tabs + $entry.Key + "`t`t" + $entry.Value)
        }
    }

    # Once we've iterated everything and the depth is at zero, we can join the root and return it as a string
    if ($Depth.Value -eq 0) {
        # VDF files always end on a newline
        return ($root -join "`n") + "`n"
    } else {
        return , $root
    }
}

#endregion

#region Binary VDF functions

#region Binary VDF Read fynctions

class BufferReader {
    <#
        .SYNOPSIS
            A class for reading values out of a binary VDF byte array
    #>
    [byte[]] $Buffer
    [int] $Offset

    BufferReader([byte[]]$Buffer, [int]$Offset) {
        $this.Buffer = $Buffer
        $this.Offset = $Offset
    }

    [string] ReadNextString( [System.Text.Encoding] $Encoding) {
        $nullTerminator = [System.Array]::IndexOf($this.Buffer, $script:TYPE_MAP, $this.Offset)

        if ($nullTerminator -eq -1) {
            throw [System.IndexOutOfRangeException] 'Could not find null terminating byte for string'
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
    if ($typeByte -eq $script:TYPE_MAPEND) {
        return [ordered]@{
            Type = $typeByte
        }
    }

    $name = $Buffer.ReadNextString([System.Text.Encoding]::GetEncoding('ISO-8859-1'))
    $value

    switch ($typeByte) {
        $script:TYPE_MAP {
            $value = Get-NextMap -Buffer $Buffer; break
        }
        $script:TYPE_STRING {
            $value = $buffer.ReadNextString([System.Text.Encoding]::UTF8); break
        }
        $script:TYPE_INT {
            $value = $Buffer.ReadNextUInt32LE(); break
        }
        $script:TYPE_FLOAT {
            $value = $Buffer.ReadNextFloatLE(); break
        }
        $script:TYPE_LONG {
            $value = $Buffer.ReadNextUInt64LE(); break
        }
        default {
            throw [System.InvalidOperationException] "Expected type-signifying byte but got unexpected value '$typeByte'"
        }
    }

    return [ordered]@{
        Type  = $typeByte
        Name  = $name
        Value = $value
    }
}

function Get-NextMap {
    param([BufferReader] $Buffer)

    $contents = [ordered]@{}

    while ($true) {
        $mapItem = Get-NextMapItem -Buffer $Buffer
        if ($mapItem.Type -eq $script:TYPE_MAPEND) {
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

#region Binary VDF write functions

function Add-String {
    param(
        [string] $Value,
        [System.Collections.Generic.List[byte]] $Contents,
        [System.Text.Encoding] $Encoding
    )

    $valArr = $Encoding.GetBytes($Value)
    if ([System.Array]::IndexOf($valArr, $script:TYPE_MAP) -ne -1) {
        throw [System.InvalidOperationException] 'Strings in VDF files cannot have null chars!'
    }

    $Contents.AddRange($valArr)
    $Contents.Add($script:TYPE_MAP)
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
        [System.Collections.Specialized.OrderedDictionary] $Map,
        [System.Collections.Generic.List[byte]] $Contents
    )

    foreach ($key in $Map.Keys) {
        $value = $Map[$key]

        switch ($value.GetType().Name) {
            'UInt32' {
                $Contents.Add($script:TYPE_INT)
                Add-String -Value $key -Contents $Contents -Encoding ([System.Text.Encoding]::GetEncoding('ISO-8859-1'))
                Add-Number -Value $value -Contents $Contents
                break
            }
            'UInt64' {
                $Contents.Add($script:TYPE_LONG)
                Add-String -Value $key -Contents $Contents -Encoding ([System.Text.Encoding]::GetEncoding('ISO-8859-1'))
                Add-Number -Value $value -Contents $Contents
                break
            }
            'Single' {
                $Contents.Add($script:TYPE_FLOAT)
                Add-String -Value $key -Contents $Contents -Encoding ([System.Text.Encoding]::GetEncoding('ISO-8859-1'))
                Add-Number -Value $value -Contents $Contents
                break
            }
            'String' {
                $Contents.Add($script:TYPE_STRING)
                Add-String -Value $key -Contents $Contents -Encoding ([System.Text.Encoding]::GetEncoding('ISO-8859-1'))
                Add-String -Value $value -Contents $Contents -Encoding ([System.Text.Encoding]::UTF8)
                break
            }
            'OrderedDictionary' {
                $Contents.Add($script:TYPE_MAP)
                Add-String -Value $key -Contents $Contents -Encoding ([System.Text.Encoding]::GetEncoding('ISO-8859-1'))
                Add-Map -Map $value -Contents $Contents
                break
            }
            default {
                throw [System.InvalidOperationException] "Type of $key '$($value.GetType().Name)' is not allowed in VDF files. VDF files can only contain strings, unsigned integers, floats, unsigned doubles, and objects"
            }
        }
    }

    $Contents.Add($script:TYPE_MAPEND)
}

function ConvertTo-BinaryVDF {
    param([System.Collections.Specialized.OrderedDictionary] $Map)

    $contents = [System.Collections.Generic.List[byte]]::new()

    Add-Map -Map $Map -Contents $contents

    return $contents.ToArray()
}
#endregion

#endregion

#region VDF manipulation functions

function Set-DefaultControllerConfigTemplate {
    <#
        .SYNOPSIS
            Updates the given config set to use the SpikeOut config templates as default for SpikeOut
        .PARAMETER ConfigSetPath
            The path to the config set to update or create if it doesn't exist yet
        .PARAMETER ConfigName
            The name of the Steam Input config
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ConfigSetPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ConfigName
    )

    # Create a default config set for the given controller if one doesn't exist yet
    if (-not(Test-Path $ConfigSetPath)) {
        $defaultConfigSet = [ordered]@{
            '"controller_config"' = [ordered]@{
                '"spikeout digital battle online"' = [ordered]@{
                    '"template"' = "`"CLOUD_spikeout digital battle online/$ConfigName`""
                }
                '"spikeout final edition"'         = [ordered]@{
                    '"template"' = "`"CLOUD_spikeout final edition/$ConfigName`""
                }
            }
        }

        [IO.File]::WriteAllText($ConfigSetPath, (ConvertTo-VDF $defaultConfigSet))
        Write-Information "Created a new config set at $configSetPath to use the custom SpikeOut control config as default"
        return
    }

    $configSet = ConvertFrom-VDF ([IO.File]::ReadAllLines($ConfigSetPath))

    # For the VDF format, all keys and values have to be encased in double-quotes
    if (-not($configSet.Contains('"controller_config"'))) {
        throw [System.IO.InvalidDataException] "Could not find required root element 'controller_config' when trying to import '$ConfigSetPath' as VDF"
    }

    $configSet['"controller_config"']['"spikeout digital battle online"'] = [ordered]@{
        '"template"' = "`"CLOUD_spikeout digital battle online/$ConfigName`""
    }

    $configSet['"controller_config"']['"spikeout final edition"'] = [ordered]@{
        '"template"' = "`"CLOUD_spikeout final edition/$ConfigName`""
    }

    [IO.File]::WriteAllText($ConfigSetPath, (ConvertTo-VDF $configSet))
    Write-Information "Updated config set at $ConfigSetPath to use the custom SpikeOut control config as default"
}

function Add-NonSteamGameShortcut {
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ $_.Contains('shortcuts') })]
        [System.Collections.Specialized.OrderedDictionary] $Map,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AppName,

        [Parameter(Mandatory)]
        [ValidateScript({ (Test-Path -Path $_ -IsValid) })]
        [string] $TargetLocation,

        [ValidateScript({ Test-Path -Path $_ -IsValid })]
        [string] $StartDir = '',

        [ValidateScript({ Test-Path -Path $_ -IsValid })]
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
    } else {
        # New key value will be the last key integer value incremented by 1, which is always equal to the current count of the shortcuts hashtable
        $newKey = $Map['shortcuts'].Count.ToString()

        # Check if generated App ID does not conflict with App IDs of existing non-Steam games in shortcuts.vdf
        $existingAppIds = [System.Collections.Generic.List[uint32]]::new()
        foreach ($shortcut in $Map['shortcuts'].GetEnumerator()) {
            if ($shortcut.Value.Contains('appid')) {
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

            if ($promptRes) { $newKey = $shortcut.Key }
            break
        }
    }

    $newShortcut = [ordered]@{}
    $newShortcut['AppName'] = $AppName
    $newShortcut['appid'] = $appId
    $newShortcut['exe'] = "`"$TargetLocation`""
    $newShortcut['StartDir'] = "`"$StartDir`""
    $newShortcut['icon'] = "`"$IconLocation`""
    $newShortcut['LaunchOptions'] = $LaunchOptions
    $newShortcut['IsHidden'] = [uint32]$IsHidden
    $newShortcut['AllowOverlay'] = [uint32]$AllowOverlay
    $newShortcut['AllowDesktopConfig'] = [uint32]$AllowDesktopConfig
    $newShortcut['openvr'] = [uint32]$OpenVr

    $Map['shortcuts'][$newKey] = $newShortcut

    return $appId
}

#endregion

#region Utility functions

function Read-BinaryChoice {
    <#
        .SYNOPSIS
            Prompts the user to make a yes/no choice
        .PARAMETER Prompt
            The text with which to prompt the user with
        .PARAMETER YesDefault
            Whether to return true by default if no answer was returned
    #>
    param(
        [Parameter(Mandatory)] [string] $Prompt,
        [Parameter(Mandatory)] [boolean] $YesDefault
    )

    $yesAnswers = @('yes', 'y', 'ye', 'yea', 'yeah')
    $noAnswers = @('no', 'n', 'nah', 'nope', 'nop')

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
    <#
        .SYNOPSIS
            Prompts the user to make a choice out of one of multiple possible answers
        .PARAMETER Prompt
            The text with which to prompt the user with
        .PARAMETER Answers
            A string array of possible answers
        .PARAMETER DefaultAnswer
            The default answer that's returned if no answer is returned after the prompt
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Prompt,

        [Parameter(Mandatory)]
        [ValidateScript({ $_.Count -gt 0 })]
        [string[]] $Answers,

        [Parameter(Mandatory)]
        $DefaultAnswer
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
    <#
        .SYNOPSIS
            Prompts the user with a FolderBrowserDialog to select the directory for the Supermodel installation
    #>

    Add-Type -AssemblyName System.Windows.Forms

    $dirSelect = New-Object System.Windows.Forms.FolderBrowserDialog
    $dirSelect.RootFolder = 'MyComputer'
    $dirSelect.Description = 'Choose in which folder to install the Sega Model 3 - Supermodel emulator...'
    $dirSelect.ShowNewFolderButton = $true

    do {
        $result = $dirSelect.ShowDialog()
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Warning 'Canceled folder selection. Aborting script...'
            exit 1
        }

        $validPath = Test-Path $dirSelect.SelectedPath
        if (-not $validPath) {
            Write-Warning "Given path '$targetPath' was not valid or could not be found. Please retry."
        }

    } while (-not $validPath)

    return $dirSelect.SelectedPath
}

function Enable-TurboMode {
    <#
        .SYNOPSIS
            Replaces the refresh rate value in the Supermodel config with the turbo mode framerate
        .DESCRIPTION
            Updates the Supermodel config to have the game run at 120% the original speed. Because the original Sega Model 3
            refresh rate comes down to something like 57.524 Hz, to have it run at 120% speed we need to set it to about
            69.0288Hz.
        .PARAMETER SupermodelConfigPath
            The file path for the Supermodel config
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ })]
        [string] $SupermodelConfigPath
    )

    $updatedConfig = (Get-Content -Path $SupermodelConfigPath -Raw).Replace("RefreshRate = 60", "RefreshRate = $TURBO_MODE_FRAMERATE")

    # We have to update the Supermodel.ini using a New-Item -Force, because in Windows Powershell (5.1) this is somehow the only consistent way to export a string to a file with UTF-8 encoding WITHOUT a BOM
    # Doing this with Out-File or Set-Content adds a BOM even if you specify UTF8 encoding, which messes up what Supermodel expects in its configuration
    $null = New-Item -Path $SupermodelConfigPath -Force -Value ($updatedConfig)
    Write-Information "Updated Supermodel.ini to use turbo mode"
}

function Get-LatestSupermodelDownload {
    <#
        .SYNOPSIS
            Downloads and extracts the archive of the newest Windows Supermodel build
        .PARAMETER TargetPath
            The path to where we want to download and setup Supermodel
        .PARAMETER SupermodelUri
            The URI for the homepage of the Supermodel emulator
        .EXAMPLE
            PS> Get-LatestSupermodelDownload -TargetPath $HOME/Supermodel -SupermodelUri 'https://supermodel3.com/'

            Downloads and unzips the latest Supermodel build to $HOME/Supermodel
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TargetPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SupermodelUri
    )

    Write-Information "Checking $SupermodelUri for the newest download..."

    $page = Invoke-WebRequest -Method Get -Uri ($SupermodelUri + 'Download.html') -UseBasicParsing

    # The link for the newest Windows build should NORMALLY be the first entry in the list of href links of the Download page that contains 'Supermodel_'
    $uriPart = ($page.Links.href | Where-Object { $_ -match 'Supermodel_' })[0]
    if ([string]::IsNullOrEmpty($uriPart)) {
        throw [System.InvalidOperationException] "Could not parse download link of latest Supermodel build at $($SupermodelUri + 'Download.html')"
    }

    $downloadUri = $SupermodelUri + $uriPart
    $extension = [System.IO.Path]::GetExtension($downloadUri)
    $outputPath = Join-Path $TargetPath ('supermodel' + $extension)

    if (-not($extension -eq '.zip')) {
        throw [System.NotSupportedException] 'Latest Supermodel build appears to not be a ZIP file. This script only supports dealing with ZIP files.'
    }

    Write-Information "Found newest version at '$downloadUri'. Downloading it to '$outputPath'..."
    Invoke-WebRequest -Method Get -Uri $downloadUri -OutFile $outputPath

    Write-Information 'Download complete! Extracting archive...'
    Expand-Archive -LiteralPath $outputPath -DestinationPath $TargetPath -Force

    $romFolder = Join-Path $TargetPath 'ROMs'
    if (-not(Test-Path $romFolder)) {
        throw [System.InvalidOperationException] "Expected to find ROM folder at $romFolder, but couldn't find it. Did the archive structure change?"
    }

    Write-Information 'Extracted Supermodel archive. Removing archive file...'
    Remove-Item -Path $outputPath -Force
    Write-Information "Successfully deleted archive at '$outputPath'.`n"
}

function Restart-Steam {
    $steamProcess = Get-Process -Name 'Steam' -ErrorAction SilentlyContinue

    # If Steam was already shut down before calling this function then we don't really consider it a terminating error anyways
    if ($null -eq $steamProcess) {
        Write-Information 'Steam was already shut down. Skipping...'
        return
    }

    $steamPath = $steamProcess.Path

    # In rare cases we may not be able to read the file path from the Steam process
    if ([string]::IsNullOrEmpty($steamPath)) {
        Write-Warning "Couldn't find path to Steam process. You'll have to restart Steam manually."
        return
    }

    # Use Steam's own shutdown mechanism for a graceful restart
    Start-Process -FilePath $steamPath -ArgumentList '-Shutdown' -Wait

    # We need to wait a bit before being able to restart Steam again. 8 secs is usually enough
    Start-Sleep -Seconds 8
    Start-Process -FilePath $steamPath
}

function New-SpikeOutLaunchOptionSet {
    <#
        .SYNOPSIS
            Prompts the user several times to construct the launch options for the SpikeOut shortcuts
    #>

    do {
        $result = @{
            # Add the -throttle option for preventing the emulator from running too fast on displays higher than 60Hz
            LaunchOptions = @('-throttle')
            TurboMode = $false
        }

        $controlSelection = Read-Choice -Answers @(1, 2) -DefaultAnswer '1' -Prompt @"
`nWhat controller type do you want to set up the keybindings for?
1) Gamepad (RECOMMENDED, more inputs to control the emulator are available using the gamepad)
2) Arcade stick/fightstick/fightpad

(NOTE: Keyboard controls will be available regardless of what options you select)
Enter 1 or 2 to select your option, or leave empty to select keybindings for gamepads by default
"@
        if ($controlSelection -eq 1) { $result.InputMethod = 'Gamepad' }
        elseif ($controlSelection -eq 2) { $result.InputMethod = 'Fightstick' }

        $windowModeSelection = Read-Choice -Answers @(1..3) -DefaultAnswer '1' -Prompt @"
`nWhich window mode do you want to use for the Supermodel emulator?
1) Fullscreen (default)
2) Windowed
3) Borderless windowed (not recommended, doesn't seem to behave like an actual borderless window)
Enter a number from 1 to 3 to select your option, or leave empty to select fullscreen by default
"@

        switch ($windowModeSelection) {
            '1' { $windowMode = '-fullscreen'; break }
            '2' { $windowMode = '-window'; break }
            '3' { $windowMode = '-borderless'; break }
        }
        $result.LaunchOptions += $windowMode

        while ($true) {
            $resolution = Read-Host "`nEnter the desired screen resolution for the Supermodel emulator window separated by a comma (for example: 1920,1080 or 2540,1440 or 1280,720 or 640,480). Leave empty to use the resolution of your current screen"

            if (($resolution -split ',').Count -eq 2) {
                # Remove whitespace in strings in case someone decides to enter it like '1920, 1080'
                $resolution = $resolution.Replace(' ', '')
                $result.LaunchOptions += "-res=$resolution"
                break
            } elseif ([string]::IsNullOrEmpty($resolution)) {
                break
            } else {
                Write-Information "$resolution did not adhere to expected resolution format 'width,height' (f.e. 640,480). Please try again"
            }
        }

        $useTrueHz = Read-Choice -Prompt @"
`nChoose what framerate you want to run SpikeOut at (Model 3 game speed is tied to framerate):
1) 57.524 fps. This is the default framerate that all Model 3 games run at, however this can cause stuttering for some systems or when capturing footage through OBS.
2) (Recommended) (Default) 60fps. This makes the game run at 104,3% the original speed, but can help fix stuttering issues.
3) 69,0288fps. This makes the game run at 120% the original speed. Use this if you want to play the game in Turbo Mode.

Enter 1, 2 or 3 to select your option, or leave empty to select 2 by default
"@ -Answers @(1..3) -DefaultAnswer '2'

        if ($useTrueHz -eq 1) { $result.LaunchOptions += "-true-hz" }
        elseif ($useTrueHz -eq 3) { $result.TurboMode = $true}

        $useSSAA = Read-Choice -Prompt "`nUse SSAA (supersampling anti-aliasing)? This will reduce jagged edges but will reduce performance.`nEnter a value from 1 to 8 to set SSAA strength, or enter nothing or 0 to disable SSAA" -Answers @(0..8) -DefaultAnswer '0'
        if ($useSSAA -ne '0') { $result.LaunchOptions += "-ss=$useSSAA" }

        $useWidescreen = Read-BinaryChoice -Prompt "`nDo you want to enable widescreen hacks for SpikeOut?`n(This lets you see more around you, but can cause unimportant graphical glitches at the sides of the screen) [Y/n]" -YesDefault:$true
        if ($useWidescreen) { $result.LaunchOptions += '-wide-bg', '-wide-screen' }

        $useCrtColors = Read-BinaryChoice -Prompt "`nApply ARI/D93 color correction to have the colors more closely resemble what you'd see on CRT displays on actual SpikeOut cabinets? [Y/n]" -YesDefault:$true
        if ($useCrtColors) { $result.LaunchOptions += '-crtcolors=1' }

        if ([string]::IsNullOrEmpty($resolution)) { $resolutionResult = 'Default' }
        else { $resolutionResult = $resolution }

        $confirmPrompt = @"
`nSelected following options:
Input method: $($result.InputMethod)
Window mode: $windowMode
Resolution: $resolutionResult
Use original 57.524Hz framerate: $($useTrueHz -eq 2)
Enable turbo mode: $($result.TurboMode)
SSAA level: $useSSAA
ARI/D93 CRT color adaptation post processing: $useCrtColors
Widescreen hacks: $useWidescreen

Continue with these options? [Y/n]
"@
        $confirmOptions = Read-BinaryChoice -Prompt $confirmPrompt -YesDefault:$true

    } while (-not $confirmOptions)

    Write-Information 'You can always later change these launch options by right-clicking on the Steam shortcuts for SpikeOut and going to Properties... -> Shortcut -> Launch Options.'
    return $result
}

function New-WindowsShortcut {
    <#
        .SYNOPSIS
            Creates a new Windows shortcut using the Windows Script Host
        .PARAMETER TargetLocation
            The location of the .exe the shortcut points to
        .PARAMETER IconLocation
            The location of the .ico file for the shortcut
        .PARAMETER LaunchOptions
            The launch options for the .exe
        .PARAMETER WorkingDirectory
            The working directory of the .exe
        .PARAMETER ShortcutLocation
            The destination of the shortcut file itself
        .PARAMETER CopyToDesktop
            Whether the shortcut file should also be copied to the desktop
        .LINK
            https://learn.microsoft.com/en-us/troubleshoot/windows-client/admin-development/create-desktop-shortcut-with-wsh
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TargetLocation,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ShortcutLocation,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $IcoLocation,

        [ValidateNotNullOrEmpty()]
        [string] $LaunchOptions = '',

        [ValidateNotNullOrEmpty()]
        [string] $WorkingDirectory = '',

        [switch] $CopyToDesktop
    )

    $WScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $WScriptShell.CreateShortcut($ShortcutLocation)
    $shortcut.TargetPath = "$TargetLocation"
    $shortcut.IconLocation = "$IcoLocation"
    $shortcut.Arguments = $LaunchOptions
    $shortcut.WorkingDirectory = "$WorkingDirectory"
    $shortcut.Save()

    if ($CopyToDesktop) {
        Copy-Item -Path $ShortcutLocation -Destination ([IO.Path]::Combine($HOME, 'Desktop', (Split-Path $ShortcutLocation -Leaf))) -Force
        Write-Information "Created shortcut at $ShortcutLocation and copied it to desktop."
    }

    $null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WScriptShell)
}

function Get-Icon {
    <#
        .SYNOPSIS
            Downloads an .ico file from the given URI to the given folder
        .PARAMETER IconsPath
            The folder where the .ico file should be downloaded to
        .PARAMETER IconName
            The filename of the downloaded .ico file
        .PARAMETER IconUri
            The download URI of the .ico file
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $IconsPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $IconName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $IconUri
    )

    if (-not(Test-Path $IconsPath)) {
        $null = New-Item $IconsPath -ItemType Directory
        Write-Information "Created icons target directory at '$IconsPath'"
    }

    $fullIcoPath = Join-Path $IconsPath $IconName
    Invoke-WebRequest -Method Get -Uri $IconUri -OutFile $fullIcoPath

    return $fullIcoPath
}

#endregion

#region Main functions

function New-RegularShortcut {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SupermodelPath
    )

    Write-Information 'Building Windows shortcuts for SpikeOut: Digital Battle Online and SpikeOut: Final Edition...'

    $romPath = Join-Path $SupermodelPath 'ROMs'
    $supermodelLauncherPath = Join-Path $SupermodelPath "Supermodel.exe"
    $selectedOptions = New-SpikeOutLaunchOptionSet
    $launchOptions = $selectedOptions.LaunchOptions -join ' '

    if ($selectedOptions.InputMethod -eq 'Fightstick') {
        $selectedInputConfig = $SUPERMODEL_NONSTEAM_FIGHTSTICK_CONFIG_URI
    } else {
        $selectedInputConfig = $SUPERMODEL_NONSTEAM_GAMEPAD_CONFIG_URI
    }

    # Download an optimized standard Supermodel config.
    $configPath = [IO.Path]::Combine($SupermodelPath, 'Config', 'Supermodel.ini')
    Invoke-WebRequest -Method Get -Uri $selectedInputConfig -OutFile $configPath
    Write-Information 'Replaced Supermodel config file with optimized control setup.'

    # Set the refresh rate in the Supermodel config to 120% speed if Turbo Mode was selected
    if ($selectedOptions.TurboMode) {
        Enable-TurboMode -SupermodelConfigPath $configPath
    }

    # The path to the ROM has to be encased in quotes in case the path contains whitespace
    $spikeoutLaunchOptions = "`"$(Join-Path $romPath 'spikeout.zip')`"" + ' ' + $launchOptions
    $spikeofeLaunchOptions = "`"$(Join-Path $romPath 'spikeofe.zip')`"" + ' ' + $launchOptions

    # Download icons to a new icons folder in the Supermodel directory
    $icoDirPath = Join-Path $SupermodelPath 'Icons'
    $spikeoutIcoPath = Get-Icon -IconsPath $icoDirPath -IconName 'spikeout.ico' -IconUri $SPIKEOUT_ICO_URI
    $spikeofeIcoPath = Get-Icon -IconsPath $icoDirPath -IconName 'spikeofe.ico' -IconUri $SPIKEOFE_ICO_URI

    New-WindowsShortcut -WorkingDirectory $SupermodelPath -TargetLocation $supermodelLauncherPath -IcoLocation $spikeoutIcoPath -LaunchOptions $spikeoutLaunchOptions -ShortcutLocation (Join-Path $SupermodelPath 'SpikeOut Digital Battle Online.lnk') -CopyToDesktop
    New-WindowsShortcut -WorkingDirectory $SupermodelPath -TargetLocation $supermodelLauncherPath -IcoLocation $spikeofeIcoPath -LaunchOptions $spikeofeLaunchOptions -ShortcutLocation (Join-Path $SupermodelPath 'SpikeOut Final Edition.lnk') -CopyToDesktop

    Write-Information 'Operation successful! Remember that you can always change the Supermodel options by editing the launch options in the SpikeOut shortcut properties.'
}

function New-SteamShortcut {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SupermodelPath
    )

    # Steam must be running so that we can read the ID of the current active Steam user in the registry
    do {
        $isSteamRunning = -not((Get-ItemPropertyValue 'HKCU:\SOFTWARE\Valve\Steam\ActiveProcess' -Name ActiveUser -ErrorAction SilentlyContinue) -in @(0, $null))

        if (-not $isSteamRunning) {
            $null = Read-Host -Prompt 'Could not detect that an instance of Steam was running on this system. Please launch Steam then press ENTER on this screen to try again'
        }
    } while (-not $isSteamRunning)

    # Download the Supermodel config tuned for use with Steam Input. This one has joystick binds removed from the native Supermodel config, so that it won't interfere with the Steam Input config.
    $configPath = [IO.Path]::Combine($SupermodelPath, 'Config', 'Supermodel.ini')
    Invoke-WebRequest -Method Get -Uri $SUPERMODEL_STEAM_CONFIG_URI -OutFile $configPath
    Write-Information "Replaced Supermodel config file with keybind setup for use with Steam Input. Make sure you don't change the binds without also changing them in the Steam Controller Configs for SpikeOut too, otherwise it might break."

    # Read Steam path and current user ID from registry
    $steamPath = Get-ItemPropertyValue 'HKCU:\SOFTWARE\Valve\Steam' -Name SteamPath
    $steamUserId = Get-ItemPropertyValue 'HKCU:\SOFTWARE\Valve\Steam\ActiveProcess' -Name ActiveUser

    $shortcutsPath = [IO.Path]::Combine($steamPath, 'userdata', $steamUserId, 'config', 'shortcuts.vdf')
    $controllerConfigPath = [IO.Path]::Combine($steamPath, 'steamapps', 'common', 'Steam Controller Configs', $steamUserId, 'config')

    if (-not (Test-Path (Split-Path $shortcutsPath -Parent))) {
        Write-Warning "Path to shortcuts.vdf ($shortcutsPath) wasn't valid. Make sure Steam is active and running before running this script"
        exit 1
    }

    if (-not (Test-Path $shortcutsPath)) {
        Write-Information 'shortcuts.vdf not yet made in Steam userdata config. Creating a new default shortcuts file...'

        # As we're dealing with a binary file, we have to initialize a default file with a byte array. This basically translates to a VDF file with one key named 'shortcuts' and an empty object value
        $defaultShortcutsValue = [byte[]] @(0, 115, 104, 111, 114, 116, 99, 117, 116, 115, 0, 8, 8)
        $null = New-Item -Path $shortcutsPath -ItemType File
        [IO.File]::WriteAllBytes($shortcutsPath, $defaultShortcutsValue)
    }

    # Create backup of shortcuts.vdf just in case
    $shortcutsBackupName = "shortcuts_backup_$(Get-Date -Format 'MMddyyyy-HHmmss').vdf"
    $shortcutBackupPath = Join-Path (Split-Path $shortcutsPath -Parent) $shortcutsBackupName
    Copy-Item -Path $shortcutsPath -Destination $shortcutBackupPath -Force
    Write-Information "Created backup of shortcuts.vdf at $shortcutBackupPath"

    # Import shortcuts.vdf
    $shortcutMap = ConvertFrom-BinaryVDF -Buffer ([System.IO.File]::ReadAllBytes($shortcutsPath))
    Write-Information 'Successfully imported shortcuts.vdf. Adding shortcuts...'

    # Construct the shortcut options
    $romPath = Join-Path $SupermodelPath 'ROMs'
    $supermodelLauncherPath = Join-Path $SupermodelPath "Supermodel.exe"

    $selectedOptions = New-SpikeOutLaunchOptionSet
    $launchOptions = $selectedOptions.LaunchOptions -join ' '

    # Set the refresh rate in the Supermodel config to 120% speed if Turbo Mode was selected
    if ($selectedOptions.TurboMode) {
        Enable-TurboMode -SupermodelConfigPath $configPath
    }

    # The path to the ROM has to be encased in quotes in case the path contains whitespace
    $spikeoutLaunchOptions = "`"$(Join-Path $romPath 'spikeout.zip')`"" + ' ' + $launchOptions
    $spikeofeLaunchOptions = "`"$(Join-Path $romPath 'spikeofe.zip')`"" + ' ' + $launchOptions

    # Download icons to a new icons folder in the Supermodel directory
    $icoDirPath = Join-Path $SupermodelPath 'Icons'
    $spikeoutIcoPath = Get-Icon -IconsPath $icoDirPath -IconName 'spikeout.ico' -IconUri $SPIKEOUT_ICO_URI
    $spikeofeIcoPath = Get-Icon -IconsPath $icoDirPath -IconName 'spikeofe.ico' -IconUri $SPIKEOFE_ICO_URI

    # Add the new SpikeOut shortcuts to the shortcuts map
    $null = Add-NonSteamGameShortcut -Map $shortcutMap -AppName 'SpikeOut: Digital Battle Online' -TargetLocation $supermodelLauncherPath -StartDir $SupermodelPath -LaunchOptions $spikeoutLaunchOptions -IconLocation $spikeoutIcoPath -AllowOverlay:$true -AllowDesktopConfig:$true
    $null = Add-NonSteamGameShortcut -Map $shortcutMap -AppName 'SpikeOut: Final Edition' -TargetLocation $supermodelLauncherPath -StartDir $SupermodelPath -LaunchOptions $spikeofeLaunchOptions -IconLocation $spikeofeIcoPath -AllowOverlay:$true -AllowDesktopConfig:$true

    # Export changes to shortcuts.vdf
    [System.IO.File]::WriteAllBytes($shortcutsPath, (ConvertTo-BinaryVDF $shortcutMap))
    Write-Information 'Successfully added non-Steam game shortcuts for SpikeOut: Digital Battle Online and SpikeOut: Final Edition to your Steam Library.'

    # Download the Steam Input config for SpikeOut depending on the selected input method, and place it in the necessary folders
    if ($selectedOptions.InputMethod -eq 'Fightstick') {
        $selectedController = $FIGHTSTICK_CONFIG_NAME
        $selectedLayoutImage = $SPIKEOUT_FIGHTSTICK_CONTROLS_URI

        Write-Information 'Downloading fightstick input binding configuration file for SpikeOut...'
        $configDownloadDest = Join-Path $env:TEMP "$FIGHTSTICK_CONFIG_NAME.vdf"
        Invoke-WebRequest -Method Get -Uri $SPIKEOUT_STEAM_INPUT_CONFIG_FIGHTSTICK_URI -OutFile $configDownloadDest
    }
    else {
        $selectedController = $GAMEPAD_CONFIG_NAME
        $selectedLayoutImage = $SPIKEOUT_GAMEPAD_CONTROLS_URI

        Write-Information 'Downloading gamepad input binding configuration file for SpikeOut...'
        $configDownloadDest = Join-Path $env:TEMP "$GAMEPAD_CONFIG_NAME.vdf"
        Invoke-WebRequest -Method Get -Uri $SPIKEOUT_STEAM_INPUT_CONFIG_GAMEPAD_URI -OutFile $configDownloadDest
    }

    $spikeoutControllerConfigPath = Join-Path $controllerConfigPath 'spikeout digital battle online'
    $spikeofeControllerConfigPath = Join-Path $controllerConfigPath 'spikeout final edition'

    # Create folders for the Steam controller configs if they don't exist yet
    if (-not (Test-Path $spikeoutControllerConfigPath)) {
        $null = New-Item -Path $controllerConfigPath -Name 'spikeout digital battle online' -ItemType Directory
        Write-Information 'Added controller config folder for SpikeOut: Digital Battle Online...'
    }

    if (-not (Test-Path $spikeofeControllerConfigPath)) {
        $null = New-Item -Path $controllerConfigPath -Name 'spikeout final edition' -ItemType Directory
        Write-Information 'Added controller config folder for SpikeOut: Final Edition...'
    }

    Copy-Item -Path $configDownloadDest -Destination $spikeoutControllerConfigPath -Force
    Copy-Item -Path $configDownloadDest -Destination $spikeofeControllerConfigPath -Force

    Write-Information 'Successfully copied SpikeOut controller configs to the controller config folder!'

    # For the config set of each controller types, set the default config for SpikeOut DBO/FE to use our custom Steam Input config
    foreach ($controllerType in $CONTROLLER_TYPES) {
        $configSetPath = Join-Path $controllerConfigPath "configset_controller_$controllerType.vdf"
        Set-DefaultControllerConfigTemplate -ConfigSetPath $configSetPath -ConfigName $selectedController
    }

    # Prompt user to restart Steam
    $cont = Read-BinaryChoice -Prompt 'Steam must be restarted for the new shortcuts to appear in your library. Restart Steam now? [Y/n]' -YesDefault:$true
    if ($cont) { Restart-Steam }

    # Show user the Steam control setup for SpikeOut
    Write-Information 'Opening an image in your browser on the SpikeOut control scheme...'
    Start-Process $selectedLayoutImage

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
        Write-Information "Starting Supermodel (Windows) + SpikeOut: Digital Battle Online / Final Edition installer v$SCRIPT_VERSION by testament_enjoyment..."
        Write-Information 'If you encounter any issues with this script, create an issue on https://github.com/GriekseEi/GriekseEi-RandomPowerShellScripts or contact me via BlueSky at: @testamentenjoyment.bsky.social'

        # Abort script if ran on non-Windows system
        if (-not($Env:OS -match 'Windows')) {
            Write-Warning 'This script is designed to only work on Windows.'
            exit 1
        }

        # Build open file dialog to pick the Supermodel emulator folder
        $selectedPath = Get-TargetFolder

        # Prompt user to download Supermodel emulator
        $cont = Read-BinaryChoice -Prompt "`nDownload the SEGA Model 3 Supermodel emulator to '$selectedPath'?`n(RECOMMENDED, this is required to be able to play SpikeOut at all. Enter N(o) only if you already have Supermodel downloaded) [Y/n]`n" -YesDefault:$true
        if ($cont) {
            Get-LatestSupermodelDownload -TargetPath $selectedPath -SupermodelUri $BASE_SUPERMODEL_URI
        } else {
            if (-not(Test-Path -Path (Join-Path $selectedPath 'Supermodel.exe'))) {
                Write-Warning "Rejected download, but could not find existing Supermodel installation at location '$selectedPath'. Aborting script..."
                exit 1
            }
        }

        # Check if Steam is installed on this system
        $isSteamInstalled = $null -ne (Get-ItemPropertyValue 'HKCU:\SOFTWARE\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue)
        if (-not $isSteamInstalled) {
            Write-Information 'Could not find Steam installation on current system...'
        }

        # Automatically create standard Windows shortcuts and exit script if no Steam installation found
        if (-not $isSteamInstalled) {
            New-RegularShortcut -SupermodelPath $selectedPath
            exit 0
        }

        $cont = Read-Choice -Answers @(1, 2) -DefaultAnswer '1' -Prompt @'
Select how you want to create your SpikeOut shortcuts:
1) (RECOMMENDED) Create shortcuts for SpikeOut in your Steam library. This also sets up a custom Steam Input config with some useful macros, that are also likely to work on all types of controllers.
2) Create standard Windows shortcuts. Uses XInput as an input system, and certain macros (pausing the emulator, savestate control) won't be available on your controller.

Enter a number (1, 2) to select your option
'@
        switch ($cont) {
            '1' { New-SteamShortcut -SupermodelPath $selectedPath; break }
            '2' { New-RegularShortcut -SupermodelPath $selectedPath; break }
        }
    } catch {
        $err = [PSCustomObject]@{
            ErrorMessage  = $_.Exception.Message
            ExceptionType = $_.Exception.GetType()
            Base          = $_.InvocationInfo.PositionMessage
            StackTrace    = $_.ScriptStackTrace
        }

        $err | Format-List
        Write-Warning 'FATAL ERROR. Terminating script...'

        exit 1
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
}

#endregion

Main