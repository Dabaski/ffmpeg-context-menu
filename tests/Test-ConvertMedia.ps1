<#
.SYNOPSIS
    Tests for the FFmpeg context menu converter.
.DESCRIPTION
    Runs unit tests and integration tests for convert-media.ps1
#>

param(
    [switch]$SkipIntegration,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectDir = Split-Path -Parent $ScriptDir
$ConverterScript = Join-Path $ProjectDir "convert-media.ps1"
$TestMediaDir = Join-Path $ScriptDir "test-media"

# Test results tracking
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Errors = @()
}

function Write-TestHeader {
    param([string]$Name)
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Message = ""
    )

    if ($Passed) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:TestResults.Passed++
    }
    else {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($Message) {
            Write-Host "         $Message" -ForegroundColor Red
        }
        $script:TestResults.Failed++
        $script:TestResults.Errors += "$Name : $Message"
    }
}

function Write-TestSkipped {
    param([string]$Name, [string]$Reason)
    Write-Host "  [SKIP] $Name - $Reason" -ForegroundColor Yellow
    $script:TestResults.Skipped++
}

# ============================================================
# Unit Tests - Test functions without actual conversion
# ============================================================

function Test-ScriptExists {
    Write-TestHeader "Script Existence Tests"

    $exists = Test-Path $ConverterScript
    Write-TestResult -Name "convert-media.ps1 exists" -Passed $exists -Message "Not found at: $ConverterScript"

    $installScript = Join-Path $ProjectDir "install.ps1"
    $exists = Test-Path $installScript
    Write-TestResult -Name "install.ps1 exists" -Passed $exists -Message "Not found at: $installScript"
}

function Test-FFmpegInstalled {
    Write-TestHeader "FFmpeg Installation Tests"

    try {
        $ffmpegPath = (Get-Command ffmpeg -ErrorAction Stop).Source
        Write-TestResult -Name "FFmpeg is in PATH" -Passed $true
        Write-Host "         Found at: $ffmpegPath" -ForegroundColor Gray
    }
    catch {
        Write-TestResult -Name "FFmpeg is in PATH" -Passed $false -Message "FFmpeg not found in PATH"
    }

    try {
        $version = & ffmpeg -version 2>&1 | Select-Object -First 1
        $hasVersion = $version -match "ffmpeg version"
        Write-TestResult -Name "FFmpeg returns version" -Passed $hasVersion
    }
    catch {
        Write-TestResult -Name "FFmpeg returns version" -Passed $false -Message $_.Exception.Message
    }
}

function Test-ScriptLoads {
    Write-TestHeader "Script Loading Tests"

    try {
        # Dot-source the script to load functions
        . $ConverterScript -TestMode
        Write-TestResult -Name "Script loads without errors" -Passed $true
    }
    catch {
        Write-TestResult -Name "Script loads without errors" -Passed $false -Message $_.Exception.Message
        return  # Can't continue other tests if script doesn't load
    }

    # Test that expected functions exist
    $expectedFunctions = @('Test-FFmpegInstalled', 'Get-MediaType', 'Convert-MediaFile', 'Invoke-Conversion')

    foreach ($func in $expectedFunctions) {
        $exists = Get-Command $func -ErrorAction SilentlyContinue
        Write-TestResult -Name "Function '$func' exists" -Passed ($null -ne $exists)
    }
}

function Test-GetMediaType {
    Write-TestHeader "Get-MediaType Tests"

    . $ConverterScript -TestMode

    $videoTests = @(
        @{ Path = "video.mp4"; Expected = "video" },
        @{ Path = "video.mkv"; Expected = "video" },
        @{ Path = "video.avi"; Expected = "video" },
        @{ Path = "video.webm"; Expected = "video" },
        @{ Path = "VIDEO.MP4"; Expected = "video" }  # Case insensitive
    )

    $audioTests = @(
        @{ Path = "audio.mp3"; Expected = "audio" },
        @{ Path = "audio.wav"; Expected = "audio" },
        @{ Path = "audio.flac"; Expected = "audio" },
        @{ Path = "AUDIO.MP3"; Expected = "audio" }  # Case insensitive
    )

    $unknownTests = @(
        @{ Path = "document.pdf"; Expected = "unknown" },
        @{ Path = "image.png"; Expected = "unknown" },
        @{ Path = "file.txt"; Expected = "unknown" }
    )

    foreach ($test in $videoTests) {
        $result = Get-MediaType -FilePath $test.Path
        Write-TestResult -Name "Get-MediaType '$($test.Path)' = video" -Passed ($result -eq $test.Expected) -Message "Got: $result"
    }

    foreach ($test in $audioTests) {
        $result = Get-MediaType -FilePath $test.Path
        Write-TestResult -Name "Get-MediaType '$($test.Path)' = audio" -Passed ($result -eq $test.Expected) -Message "Got: $result"
    }

    foreach ($test in $unknownTests) {
        $result = Get-MediaType -FilePath $test.Path
        Write-TestResult -Name "Get-MediaType '$($test.Path)' = unknown" -Passed ($result -eq $test.Expected) -Message "Got: $result"
    }
}

function Test-ConvertMediaFileCommand {
    Write-TestHeader "Convert-MediaFile Command Generation Tests"

    . $ConverterScript -TestMode

    # Test video format commands
    $testCases = @(
        @{ Source = "C:\test\video.mp4"; Format = "mkv"; ExpectedExt = "mkv" },
        @{ Source = "C:\test\video.mkv"; Format = "mp4"; ExpectedExt = "mp4" },
        @{ Source = "C:\test\video.avi"; Format = "webm"; ExpectedExt = "webm" },
        @{ Source = "C:\test\audio.mp3"; Format = "wav"; ExpectedExt = "wav" },
        @{ Source = "C:\test\audio.wav"; Format = "flac"; ExpectedExt = "flac" }
    )

    foreach ($test in $testCases) {
        try {
            $result = Convert-MediaFile -Source $test.Source -Format $test.Format
            $hasOutput = $result.OutputFile -like "*.$($test.ExpectedExt)"
            $hasCommand = $result.Command -like "ffmpeg*"
            Write-TestResult -Name "Convert $($test.Source) to $($test.Format)" -Passed ($hasOutput -and $hasCommand)
        }
        catch {
            Write-TestResult -Name "Convert $($test.Source) to $($test.Format)" -Passed $false -Message $_.Exception.Message
        }
    }

    # Test invalid format
    try {
        $result = Convert-MediaFile -Source "C:\test\video.mp4" -Format "invalid_format"
        Write-TestResult -Name "Reject invalid format" -Passed $false -Message "Should have thrown exception"
    }
    catch {
        Write-TestResult -Name "Reject invalid format" -Passed $true
    }
}

function Test-OutputFileNaming {
    Write-TestHeader "Output File Naming Tests"

    . $ConverterScript -TestMode

    # Test basic naming
    $result = Convert-MediaFile -Source "C:\test\my video.mp4" -Format "mkv"
    $expectedName = "my video.mkv"
    $actualName = [System.IO.Path]::GetFileName($result.OutputFile)
    Write-TestResult -Name "Preserves filename with spaces" -Passed ($actualName -eq $expectedName) -Message "Got: $actualName"

    # Test custom output directory
    $result = Convert-MediaFile -Source "C:\test\video.mp4" -Format "mkv" -OutputDirectory "D:\output"
    $expectedDir = "D:\output"
    $actualDir = [System.IO.Path]::GetDirectoryName($result.OutputFile)
    Write-TestResult -Name "Uses custom output directory" -Passed ($actualDir -eq $expectedDir) -Message "Got: $actualDir"
}

# ============================================================
# Integration Tests - Require actual files and conversion
# ============================================================

function New-TestMediaFiles {
    Write-TestHeader "Creating Test Media Files"

    if (-not (Test-Path $TestMediaDir)) {
        New-Item -ItemType Directory -Path $TestMediaDir -Force | Out-Null
    }

    # Create a simple test video using ffmpeg (1 second, solid color)
    $testVideo = Join-Path $TestMediaDir "test_video.mp4"
    if (-not (Test-Path $testVideo)) {
        Write-Host "  Creating test video..." -ForegroundColor Gray
        $argString = "-f lavfi -i `"color=c=blue:s=320x240:d=1`" -f lavfi -i `"anullsrc=r=44100:cl=stereo`" -t 1 -c:v libx264 -c:a aac -y `"$testVideo`""
        $proc = Start-Process -FilePath "ffmpeg" -ArgumentList $argString -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -eq 0 -and (Test-Path $testVideo)) {
            Write-Host "  Created: $testVideo" -ForegroundColor Green
        }
        else {
            Write-Host "  Failed to create test video" -ForegroundColor Red
            return $false
        }
    }

    # Create a simple test audio using ffmpeg (1 second, sine wave)
    $testAudio = Join-Path $TestMediaDir "test_audio.mp3"
    if (-not (Test-Path $testAudio)) {
        Write-Host "  Creating test audio..." -ForegroundColor Gray
        $argString = "-f lavfi -i `"sine=frequency=440:duration=1`" -c:a libmp3lame -y `"$testAudio`""
        $proc = Start-Process -FilePath "ffmpeg" -ArgumentList $argString -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -eq 0 -and (Test-Path $testAudio)) {
            Write-Host "  Created: $testAudio" -ForegroundColor Green
        }
        else {
            Write-Host "  Failed to create test audio" -ForegroundColor Red
            return $false
        }
    }

    return $true
}

function Test-VideoConversion {
    Write-TestHeader "Video Conversion Tests"

    . $ConverterScript -TestMode

    $testVideo = Join-Path $TestMediaDir "test_video.mp4"
    if (-not (Test-Path $testVideo)) {
        Write-TestSkipped -Name "Video conversion" -Reason "Test video not found"
        return
    }

    $formats = @('mkv', 'webm', 'avi')

    foreach ($format in $formats) {
        $outputFile = Join-Path $TestMediaDir "test_video.$format"

        # Remove existing output
        if (Test-Path $outputFile) {
            Remove-Item $outputFile -Force
        }

        try {
            $result = Invoke-Conversion -Source $testVideo -Format $format -OutputDirectory $TestMediaDir

            $success = $result.Success -and (Test-Path $result.OutputFile)
            Write-TestResult -Name "Convert MP4 to $($format.ToUpper())" -Passed $success -Message $result.Message

            # Verify output file has content
            if ($success) {
                $fileSize = (Get-Item $result.OutputFile).Length
                Write-TestResult -Name "Output $format has content" -Passed ($fileSize -gt 0) -Message "Size: $fileSize bytes"
            }
        }
        catch {
            Write-TestResult -Name "Convert MP4 to $($format.ToUpper())" -Passed $false -Message $_.Exception.Message
        }
    }
}

function Test-AudioConversion {
    Write-TestHeader "Audio Conversion Tests"

    . $ConverterScript -TestMode

    $testAudio = Join-Path $TestMediaDir "test_audio.mp3"
    if (-not (Test-Path $testAudio)) {
        Write-TestSkipped -Name "Audio conversion" -Reason "Test audio not found"
        return
    }

    $formats = @('wav', 'flac', 'ogg')

    foreach ($format in $formats) {
        $outputFile = Join-Path $TestMediaDir "test_audio.$format"

        # Remove existing output
        if (Test-Path $outputFile) {
            Remove-Item $outputFile -Force
        }

        try {
            $result = Invoke-Conversion -Source $testAudio -Format $format -OutputDirectory $TestMediaDir

            $success = $result.Success -and (Test-Path $result.OutputFile)
            Write-TestResult -Name "Convert MP3 to $($format.ToUpper())" -Passed $success -Message $result.Message

            # Verify output file has content
            if ($success) {
                $fileSize = (Get-Item $result.OutputFile).Length
                Write-TestResult -Name "Output $format has content" -Passed ($fileSize -gt 0) -Message "Size: $fileSize bytes"
            }
        }
        catch {
            Write-TestResult -Name "Convert MP3 to $($format.ToUpper())" -Passed $false -Message $_.Exception.Message
        }
    }
}

function Test-AudioExtractFromVideo {
    Write-TestHeader "Audio Extract From Video Tests"

    . $ConverterScript -TestMode

    $testVideo = Join-Path $TestMediaDir "test_video.mp4"
    if (-not (Test-Path $testVideo)) {
        Write-TestSkipped -Name "Audio extraction" -Reason "Test video not found"
        return
    }

    $outputFile = Join-Path $TestMediaDir "test_video.mp3"

    # Remove existing output
    if (Test-Path $outputFile) {
        Remove-Item $outputFile -Force
    }

    try {
        $result = Invoke-Conversion -Source $testVideo -Format "mp3" -OutputDirectory $TestMediaDir

        $success = $result.Success -and (Test-Path $result.OutputFile)
        Write-TestResult -Name "Extract audio as MP3 from video" -Passed $success -Message $result.Message

        if ($success) {
            $fileSize = (Get-Item $result.OutputFile).Length
            Write-TestResult -Name "Extracted audio has content" -Passed ($fileSize -gt 0) -Message "Size: $fileSize bytes"
        }
    }
    catch {
        Write-TestResult -Name "Extract audio as MP3 from video" -Passed $false -Message $_.Exception.Message
    }
}

function Test-RegistryInstallation {
    Write-TestHeader "Registry Installation Tests (Simulation)"

    # We don't actually modify registry in tests, just verify the install script syntax

    $installScript = Join-Path $ProjectDir "install.ps1"

    try {
        # Parse the script without executing
        $null = [System.Management.Automation.Language.Parser]::ParseFile($installScript, [ref]$null, [ref]$null)
        Write-TestResult -Name "install.ps1 has valid syntax" -Passed $true
    }
    catch {
        Write-TestResult -Name "install.ps1 has valid syntax" -Passed $false -Message $_.Exception.Message
    }

    # Verify expected registry paths would be created
    $content = Get-Content $installScript -Raw

    $checks = @(
        @{ Name = "Uses HKCU registry hive"; Pattern = "HKCU:" },
        @{ Name = "Creates shell commands"; Pattern = "shell" },
        @{ Name = "Has uninstall capability"; Pattern = "Uninstall" }
    )

    foreach ($check in $checks) {
        $found = $content -like "*$($check.Pattern)*"
        Write-TestResult -Name $check.Name -Passed $found
    }
}

function Remove-TestMediaFiles {
    if (Test-Path $TestMediaDir) {
        Write-Host "`nCleaning up test files..." -ForegroundColor Gray
        Remove-Item $TestMediaDir -Recurse -Force
    }
}

function Show-TestSummary {
    Write-Host "`n" + ("=" * 50) -ForegroundColor White
    Write-Host "TEST SUMMARY" -ForegroundColor White
    Write-Host ("=" * 50) -ForegroundColor White

    Write-Host "  Passed:  $($script:TestResults.Passed)" -ForegroundColor Green
    Write-Host "  Failed:  $($script:TestResults.Failed)" -ForegroundColor $(if ($script:TestResults.Failed -gt 0) { "Red" } else { "Gray" })
    Write-Host "  Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow

    if ($script:TestResults.Errors.Count -gt 0) {
        Write-Host "`nFailed Tests:" -ForegroundColor Red
        foreach ($error in $script:TestResults.Errors) {
            Write-Host "  - $error" -ForegroundColor Red
        }
    }

    Write-Host ""

    return $script:TestResults.Failed -eq 0
}

# ============================================================
# Main Test Runner
# ============================================================

Write-Host @"
╔═══════════════════════════════════════════════════════════════╗
║         FFmpeg Context Menu Converter - Test Suite            ║
╚═══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Run unit tests
Test-ScriptExists
Test-FFmpegInstalled
Test-ScriptLoads
Test-GetMediaType
Test-ConvertMediaFileCommand
Test-OutputFileNaming
Test-RegistryInstallation

# Run integration tests
if (-not $SkipIntegration) {
    Write-Host "`n--- Integration Tests ---" -ForegroundColor Magenta

    $mediaCreated = New-TestMediaFiles
    if ($mediaCreated) {
        Test-VideoConversion
        Test-AudioConversion
        Test-AudioExtractFromVideo
        Remove-TestMediaFiles
    }
    else {
        Write-Host "  Skipping integration tests - could not create test media" -ForegroundColor Yellow
    }
}
else {
    Write-Host "`n--- Skipping Integration Tests ---" -ForegroundColor Yellow
}

# Show summary
$allPassed = Show-TestSummary

# Return exit code
if ($allPassed) {
    exit 0
}
else {
    exit 1
}
