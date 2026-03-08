<#
.SYNOPSIS
    FFmpeg media converter for Windows context menu integration.
.DESCRIPTION
    Converts video and audio files to various formats using ffmpeg.
    Designed to be called from Windows Explorer right-click context menu.
.PARAMETER InputFile
    Path to the source media file.
.PARAMETER TargetFormat
    Optional: Target format to convert to. If not specified, shows a selection dialog.
.PARAMETER OutputDir
    Optional: Output directory. Defaults to same directory as input file.
#>

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$InputFile,

    [Parameter(Mandatory=$false)]
    [string]$TargetFormat,

    [Parameter(Mandatory=$false)]
    [string]$OutputDir,

    [Parameter(Mandatory=$false)]
    [switch]$TestMode
)

# Configuration
$script:Config = @{
    VideoFormats = @{
        'mp4'  = @{ Extension = 'mp4';  Args = '-c:v libx264 -crf 23 -preset medium -c:a aac -b:a 192k' }
        'mkv'  = @{ Extension = 'mkv';  Args = '-c:v libx264 -crf 23 -preset medium -c:a aac -b:a 192k' }
        'webm' = @{ Extension = 'webm'; Args = '-c:v libvpx-vp9 -crf 30 -b:v 0 -c:a libopus -b:a 128k' }
        'avi'  = @{ Extension = 'avi';  Args = '-c:v mpeg4 -q:v 5 -c:a mp3 -b:a 192k' }
        'mov'  = @{ Extension = 'mov';  Args = '-c:v libx264 -crf 23 -c:a aac -b:a 192k' }
        'gif'  = @{ Extension = 'gif';  Args = '-vf "fps=15,scale=480:-1:flags=lanczos" -loop 0' }
    }
    AudioFormats = @{
        'mp3'  = @{ Extension = 'mp3';  Args = '-vn -c:a libmp3lame -q:a 2' }
        'aac'  = @{ Extension = 'aac';  Args = '-vn -c:a aac -b:a 192k' }
        'wav'  = @{ Extension = 'wav';  Args = '-vn -c:a pcm_s16le' }
        'flac' = @{ Extension = 'flac'; Args = '-vn -c:a flac' }
        'ogg'  = @{ Extension = 'ogg';  Args = '-vn -c:a libvorbis -q:a 5' }
        'opus' = @{ Extension = 'opus'; Args = '-vn -c:a libopus -b:a 128k' }
    }
    SupportedInputExtensions = @('.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.wmv', '.m4v',
                                  '.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma', '.opus')
}

function Test-FFmpegInstalled {
    try {
        $null = & ffmpeg -version 2>&1
        return $true
    }
    catch {
        return $false
    }
}

function Get-MediaType {
    param([string]$FilePath)

    $videoExtensions = @('.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.wmv', '.m4v')
    $audioExtensions = @('.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma', '.opus')

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()

    if ($videoExtensions -contains $ext) { return 'video' }
    if ($audioExtensions -contains $ext) { return 'audio' }
    return 'unknown'
}

function Show-FormatSelectionDialog {
    param([string]$MediaType)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Convert to Format"
    $form.Size = New-Object System.Drawing.Size(300, 350)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(10, 15)
    $label.Size = New-Object System.Drawing.Size(260, 20)
    $label.Text = "Select target format:"
    $form.Controls.Add($label)

    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(10, 40)
    $listBox.Size = New-Object System.Drawing.Size(260, 200)

    # Add formats based on media type
    if ($MediaType -eq 'video') {
        $script:Config.VideoFormats.Keys | Sort-Object | ForEach-Object { [void]$listBox.Items.Add($_.ToUpper()) }
        [void]$listBox.Items.Add("---AUDIO EXTRACT---")
        $script:Config.AudioFormats.Keys | Sort-Object | ForEach-Object { [void]$listBox.Items.Add($_.ToUpper() + " (audio only)") }
    }
    else {
        $script:Config.AudioFormats.Keys | Sort-Object | ForEach-Object { [void]$listBox.Items.Add($_.ToUpper()) }
    }

    $listBox.SelectedIndex = 0
    $form.Controls.Add($listBox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(60, 260)
    $okButton.Size = New-Object System.Drawing.Size(75, 30)
    $okButton.Text = "Convert"
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $okButton
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(145, 260)
    $cancelButton.Size = New-Object System.Drawing.Size(75, 30)
    $cancelButton.Text = "Cancel"
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancelButton
    $form.Controls.Add($cancelButton)

    $form.TopMost = $true
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $selected = $listBox.SelectedItem
        if ($selected -and $selected -ne "---AUDIO EXTRACT---") {
            return $selected.ToLower() -replace ' \(audio only\)', ''
        }
    }
    return $null
}

function Convert-MediaFile {
    param(
        [string]$Source,
        [string]$Format,
        [string]$OutputDirectory
    )

    $mediaType = Get-MediaType -FilePath $Source
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Source)

    if (-not $OutputDirectory) {
        $OutputDirectory = [System.IO.Path]::GetDirectoryName($Source)
    }

    # Determine format settings
    $formatConfig = $null
    $isAudioExtract = $false

    if ($script:Config.VideoFormats.ContainsKey($Format)) {
        $formatConfig = $script:Config.VideoFormats[$Format]
    }
    elseif ($script:Config.AudioFormats.ContainsKey($Format)) {
        $formatConfig = $script:Config.AudioFormats[$Format]
        $isAudioExtract = ($mediaType -eq 'video')
    }
    else {
        throw "Unsupported format: $Format"
    }

    $outputFile = Join-Path $OutputDirectory "$baseName.$($formatConfig.Extension)"

    # Handle file name collision
    $counter = 1
    while (Test-Path $outputFile) {
        $outputFile = Join-Path $OutputDirectory "$baseName`_$counter.$($formatConfig.Extension)"
        $counter++
    }

    # Build ffmpeg command
    $ffmpegArgs = @(
        '-i', "`"$Source`"",
        '-y'
    ) + ($formatConfig.Args -split ' ') + @("`"$outputFile`"")

    return @{
        Command = "ffmpeg $($ffmpegArgs -join ' ')"
        OutputFile = $outputFile
        Args = $ffmpegArgs
    }
}

function Invoke-Conversion {
    param(
        [string]$Source,
        [string]$Format,
        [string]$OutputDirectory
    )

    $conversion = Convert-MediaFile -Source $Source -Format $Format -OutputDirectory $OutputDirectory

    Write-Host "Converting: $Source"
    Write-Host "Output: $($conversion.OutputFile)"
    Write-Host "Command: $($conversion.Command)"
    Write-Host ""

    $process = Start-Process -FilePath "ffmpeg" -ArgumentList $conversion.Args -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        return @{
            Success = $true
            OutputFile = $conversion.OutputFile
            Message = "Conversion complete: $($conversion.OutputFile)"
        }
    }
    else {
        return @{
            Success = $false
            OutputFile = $null
            Message = "Conversion failed with exit code: $($process.ExitCode)"
        }
    }
}

# Main execution
function Main {
    # Validate input file parameter
    if (-not $InputFile) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "No input file specified. Use: convert-media.ps1 <file>",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }

    # Validate ffmpeg
    if (-not (Test-FFmpegInstalled)) {
        [System.Windows.Forms.MessageBox]::Show(
            "FFmpeg is not installed or not in PATH.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }

    # Validate input file
    if (-not (Test-Path $InputFile)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Input file not found: $InputFile",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }

    # Validate input file extension
    $ext = [System.IO.Path]::GetExtension($InputFile).ToLower()
    if ($script:Config.SupportedInputExtensions -notcontains $ext) {
        [System.Windows.Forms.MessageBox]::Show(
            "Unsupported file type: $ext",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }

    $mediaType = Get-MediaType -FilePath $InputFile

    # Get target format
    if (-not $TargetFormat) {
        Add-Type -AssemblyName System.Windows.Forms
        $TargetFormat = Show-FormatSelectionDialog -MediaType $mediaType
        if (-not $TargetFormat) {
            exit 0  # User cancelled
        }
    }

    # Perform conversion
    try {
        $result = Invoke-Conversion -Source $InputFile -Format $TargetFormat -OutputDirectory $OutputDir

        Add-Type -AssemblyName System.Windows.Forms
        if ($result.Success) {
            [System.Windows.Forms.MessageBox]::Show(
                $result.Message,
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                $result.Message,
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "Error: $_",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }
}

# Only run Main if not being dot-sourced or in test mode
if ($MyInvocation.InvocationName -ne '.' -and -not $TestMode) {
    Main
}
