param(
    [switch]$SelfTest,
    [switch]$DebugWindow,
    [switch]$Demo
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:LogPath = Join-Path $script:AppRoot 'logs\cr7-pet.log'
$script:StatePath = Join-Path $script:AppRoot 'state.json'
$configPath = Join-Path $script:AppRoot 'config.json'
$skinsPath = Join-Path $script:AppRoot 'assets\skins'

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:LogPath) | Out-Null

function Write-PetLog {
    param([string]$Message)
    try {
        Add-Content -LiteralPath $script:LogPath -Value ('{0:u} {1}' -f (Get-Date), $Message) -Encoding UTF8
    }
    catch {
    }
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Management
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$nativeCode = @'
using System;
using System.Diagnostics;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace CR7PetNative
{
    public enum EDataFlow { eRender = 0, eCapture = 1, eAll = 2 }
    public enum ERole { eConsole = 0, eMultimedia = 1, eCommunications = 2 }

    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject { }

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(EDataFlow dataFlow, int stateMask, IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice endpoint);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        [PreserveSig]
        int Activate(ref Guid interfaceId, int classContext, IntPtr activationParameters,
            [MarshalAs(UnmanagedType.IUnknown)] out object instance);
    }

    [ComImport]
    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioEndpointVolume
    {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int GetChannelCount(out uint count);
        [PreserveSig] int SetMasterVolumeLevel(float level, IntPtr eventContext);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level, IntPtr eventContext);
        [PreserveSig] int GetMasterVolumeLevel(out float level);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(uint channel, float level, IntPtr eventContext);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, IntPtr eventContext);
        [PreserveSig] int GetChannelVolumeLevel(uint channel, out float level);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool muted, IntPtr eventContext);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool muted);
        [PreserveSig] int GetVolumeStepInfo(out uint step, out uint stepCount);
        [PreserveSig] int VolumeStepUp(IntPtr eventContext);
        [PreserveSig] int VolumeStepDown(IntPtr eventContext);
        [PreserveSig] int QueryHardwareSupport(out uint hardwareSupportMask);
        [PreserveSig] int GetVolumeRange(out float minDb, out float maxDb, out float incrementDb);
    }

    public sealed class AudioSnapshot
    {
        public float Volume { get; set; }
        public bool Muted { get; set; }
    }

    public static class Sensors
    {
        private const int CLSCTX_ALL = 23;

        public static AudioSnapshot ReadAudio()
        {
            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            IAudioEndpointVolume endpoint = null;
            try
            {
                enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
                Marshal.ThrowExceptionForHR(
                    enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eConsole, out device));
                Guid interfaceId = typeof(IAudioEndpointVolume).GUID;
                object activated;
                Marshal.ThrowExceptionForHR(
                    device.Activate(ref interfaceId, CLSCTX_ALL, IntPtr.Zero, out activated));
                endpoint = (IAudioEndpointVolume)activated;
                float volume;
                bool muted;
                Marshal.ThrowExceptionForHR(endpoint.GetMasterVolumeLevelScalar(out volume));
                Marshal.ThrowExceptionForHR(endpoint.GetMute(out muted));
                return new AudioSnapshot { Volume = volume, Muted = muted };
            }
            finally
            {
                if (endpoint != null && Marshal.IsComObject(endpoint)) Marshal.FinalReleaseComObject(endpoint);
                if (device != null && Marshal.IsComObject(device)) Marshal.FinalReleaseComObject(device);
                if (enumerator != null && Marshal.IsComObject(enumerator)) Marshal.FinalReleaseComObject(enumerator);
            }
        }

        public static int ReadBrightness()
        {
            try
            {
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(
                    @"root\WMI", "SELECT Active, CurrentBrightness FROM WmiMonitorBrightness"))
                {
                    foreach (ManagementObject monitor in searcher.Get())
                    {
                        bool active = monitor["Active"] == null || Convert.ToBoolean(monitor["Active"]);
                        if (active && monitor["CurrentBrightness"] != null)
                            return Convert.ToInt32(monitor["CurrentBrightness"]);
                    }
                }
            }
            catch { return -1; }
            return -1;
        }
    }

    public static class KeyboardHook
    {
        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int VK_BACK = 0x08;
        private const int VK_RETURN = 0x0D;
        private const int VK_7 = 0x37;
        private const int VK_NUMPAD7 = 0x67;
        private static LowLevelKeyboardProc callback = HookCallback;
        private static IntPtr hook = IntPtr.Zero;
        private static int switchCounter = 0;
        private static int siuCounter = 0;
        private static int bicycleCounter = 0;
        private static long lastSwitchMilliseconds = 0;
        private static long lastSiuMilliseconds = 0;
        private static long lastBicycleMilliseconds = 0;

        public static int SwitchCounter { get { return Volatile.Read(ref switchCounter); } }
        public static int SiuCounter { get { return Volatile.Read(ref siuCounter); } }
        public static int BicycleCounter { get { return Volatile.Read(ref bicycleCounter); } }
        public static bool IsInstalled { get { return hook != IntPtr.Zero; } }

        public static bool Install()
        {
            if (hook != IntPtr.Zero) return true;
            using (Process process = Process.GetCurrentProcess())
            using (ProcessModule module = process.MainModule)
            {
                hook = SetWindowsHookEx(WH_KEYBOARD_LL, callback, GetModuleHandle(module.ModuleName), 0);
            }
            return hook != IntPtr.Zero;
        }

        public static void Uninstall()
        {
            if (hook != IntPtr.Zero)
            {
                UnhookWindowsHookEx(hook);
                hook = IntPtr.Zero;
            }
        }

        private static IntPtr HookCallback(int code, IntPtr message, IntPtr data)
        {
            if (code >= 0 && (message == (IntPtr)WM_KEYDOWN || message == (IntPtr)WM_SYSKEYDOWN))
            {
                int key = Marshal.ReadInt32(data);
                int flags = Marshal.ReadInt32(data, 8);
                if ((flags & 0x10) != 0)
                    return CallNextHookEx(hook, code, message, data);
                if (key == VK_7 || key == VK_NUMPAD7)
                {
                    long now = DateTime.UtcNow.Ticks / TimeSpan.TicksPerMillisecond;
                    long previous = Interlocked.Read(ref lastSwitchMilliseconds);
                    if (now - previous > 320)
                    {
                        Interlocked.Exchange(ref lastSwitchMilliseconds, now);
                        Interlocked.Increment(ref switchCounter);
                    }
                }
                else if (key == VK_RETURN)
                {
                    long now = DateTime.UtcNow.Ticks / TimeSpan.TicksPerMillisecond;
                    long previous = Interlocked.Read(ref lastSiuMilliseconds);
                    if (now - previous > 420)
                    {
                        Interlocked.Exchange(ref lastSiuMilliseconds, now);
                        Interlocked.Increment(ref siuCounter);
                    }
                }
                else if (key == VK_BACK)
                {
                    long now = DateTime.UtcNow.Ticks / TimeSpan.TicksPerMillisecond;
                    long previous = Interlocked.Read(ref lastBicycleMilliseconds);
                    if (now - previous > 420)
                    {
                        Interlocked.Exchange(ref lastBicycleMilliseconds, now);
                        Interlocked.Increment(ref bicycleCounter);
                    }
                }
            }
            return CallNextHookEx(hook, code, message, data);
        }

        private delegate IntPtr LowLevelKeyboardProc(int code, IntPtr message, IntPtr data);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc callback, IntPtr module, uint threadId);
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr GetModuleHandle(string moduleName);
    }

    public sealed class ForegroundWindowInfo
    {
        public IntPtr Handle { get; set; }
        public int ProcessId { get; set; }
        public string ProcessName { get; set; }
        public string Title { get; set; }
    }

    public static class VSCodeBridge
    {
        private const int GWL_EXSTYLE = -20;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const uint INPUT_KEYBOARD = 1;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const ushort VK_CONTROL = 0x11;
        private const ushort VK_RETURN = 0x0D;
        private const int SW_RESTORE = 9;

        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT
        {
            public uint type;
            public InputUnion data;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct InputUnion
        {
            [FieldOffset(0)] public KEYBDINPUT keyboard;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct KEYBDINPUT
        {
            public ushort virtualKey;
            public ushort scanCode;
            public uint flags;
            public uint time;
            public UIntPtr extraInfo;
        }

        public static bool IsAvailable()
        {
            return Marshal.SizeOf(typeof(INPUT)) > 0;
        }

        public static ForegroundWindowInfo GetForegroundInfo()
        {
            IntPtr handle = GetForegroundWindow();
            if (handle == IntPtr.Zero) return null;

            uint processId;
            GetWindowThreadProcessId(handle, out processId);
            string processName = "";
            try { processName = Process.GetProcessById((int)processId).ProcessName; }
            catch { }

            int length = GetWindowTextLength(handle);
            StringBuilder title = new StringBuilder(Math.Max(1, length + 1));
            GetWindowText(handle, title, title.Capacity);
            return new ForegroundWindowInfo
            {
                Handle = handle,
                ProcessId = (int)processId,
                ProcessName = processName,
                Title = title.ToString()
            };
        }

        public static void MakeNoActivate(IntPtr handle)
        {
            if (handle == IntPtr.Zero) return;
            int style = GetWindowLong(handle, GWL_EXSTYLE);
            SetWindowLong(handle, GWL_EXSTYLE, style | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
        }

        public static bool RestoreWindow(IntPtr handle)
        {
            if (handle == IntPtr.Zero || !IsWindow(handle)) return false;
            ShowWindowAsync(handle, SW_RESTORE);
            return SetForegroundWindow(handle);
        }

        public static bool SendSubmitKey(bool controlEnter)
        {
            INPUT[] inputs = controlEnter ? new INPUT[4] : new INPUT[2];
            int index = 0;
            if (controlEnter) inputs[index++] = Key(VK_CONTROL, false);
            inputs[index++] = Key(VK_RETURN, false);
            inputs[index++] = Key(VK_RETURN, true);
            if (controlEnter) inputs[index++] = Key(VK_CONTROL, true);
            return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT))) == inputs.Length;
        }

        private static INPUT Key(ushort virtualKey, bool keyUp)
        {
            return new INPUT
            {
                type = INPUT_KEYBOARD,
                data = new InputUnion
                {
                    keyboard = new KEYBDINPUT
                    {
                        virtualKey = virtualKey,
                        scanCode = 0,
                        flags = keyUp ? KEYEVENTF_KEYUP : 0,
                        time = 0,
                        extraInfo = UIntPtr.Zero
                    }
                }
            };
        }

        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr handle, StringBuilder text, int count);
        [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr handle);
        [DllImport("user32.dll", SetLastError = true)] private static extern int GetWindowLong(IntPtr handle, int index);
        [DllImport("user32.dll", SetLastError = true)] private static extern int SetWindowLong(IntPtr handle, int index, int value);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr handle);
        [DllImport("user32.dll")] private static extern bool ShowWindowAsync(IntPtr handle, int command);
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr handle);
        [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, INPUT[] inputs, int size);
    }
}
'@

Add-Type -TypeDefinition $nativeCode -ReferencedAssemblies @(
    'System.dll',
    'System.Core.dll',
    'System.Management.dll'
)

$script:SkinSlugs = @(
    'purple-noodle',
    'young-ronaldo',
    'juventus-half',
    'portugal-euro',
    'white-gold'
)
$script:SkinNames = @(
    'Purple Noodle',
    'Young Ronaldo',
    'Juventus Half & Half',
    'Portugal Euro Red',
    'White & Gold'
)

$missingAssets = New-Object System.Collections.Generic.List[string]
foreach ($slug in $script:SkinSlugs) {
    $frameDir = Join-Path $skinsPath (Join-Path $slug 'frames')
    for ($index = 1; $index -le 25; $index++) {
        $pattern = '{0:D2}_*.png' -f $index
        if (@(Get-ChildItem -LiteralPath $frameDir -Filter $pattern -File -ErrorAction SilentlyContinue).Count -ne 1) {
            $missingAssets.Add((Join-Path $frameDir $pattern))
        }
    }
}

if ($SelfTest) {
    $alphaErrors = New-Object System.Collections.Generic.List[string]
    foreach ($slug in $script:SkinSlugs) {
        $frameDir = Join-Path $skinsPath (Join-Path $slug 'frames')
        foreach ($file in @(Get-ChildItem -LiteralPath $frameDir -Filter '*.png' -File | Sort-Object Name)) {
            try {
                $bitmap = [System.Drawing.Bitmap]::FromFile($file.FullName)
                if ($bitmap.GetPixel(0, 0).A -ne 0 -or $bitmap.GetPixel(($bitmap.Width - 1), 0).A -ne 0) {
                    $alphaErrors.Add($file.FullName)
                }
                $bitmap.Dispose()
            }
            catch {
                $alphaErrors.Add($file.FullName)
            }
        }
    }

    $audio = $null
    $audioError = $null
    try { $audio = [CR7PetNative.Sensors]::ReadAudio() }
    catch { $audioError = $_.Exception.Message }
    $brightness = [CR7PetNative.Sensors]::ReadBrightness()
    $hookInstalled = [CR7PetNative.KeyboardHook]::Install()
    [CR7PetNative.KeyboardHook]::Uninstall()

    [pscustomobject]@{
        engine = 'WPF per-pixel alpha'
        language = 'English'
        skinsFound = $script:SkinSlugs.Count
        framesFound = (125 - $missingAssets.Count)
        framesMissing = @($missingAssets)
        alphaCornerErrors = @($alphaErrors)
        globalSevenHook = $hookInstalled
        globalEnterSiu = $hookInstalled
        globalBackspaceBicycle = $hookInstalled
        globalHotkeysPassThrough = $true
        vsCodeSubmitBridge = [CR7PetNative.VSCodeBridge]::IsAvailable()
        audioVolumePercent = if ($audio) { [math]::Round($audio.Volume * 100) } else { $null }
        audioMuted = if ($audio) { $audio.Muted } else { $null }
        audioError = $audioError
        brightnessPercent = $brightness
        brightnessSupported = ($brightness -ge 0)
    } | ConvertTo-Json -Depth 4
    $passed = $missingAssets.Count -eq 0 -and $alphaErrors.Count -eq 0 -and $hookInstalled -and [CR7PetNative.VSCodeBridge]::IsAvailable() -and -not $audioError
    exit $(if ($passed) { 0 } else { 1 })
}

if ($missingAssets.Count -gt 0) {
    [System.Windows.MessageBox]::Show(
        ('Animation assets are missing.' + [Environment]::NewLine + ($missingAssets -join [Environment]::NewLine)),
        'VS Code Pet',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\CR7CodexPet.WPF.SingleInstance', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

function Import-WpfBitmap {
    param([string]$Path)
    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat
    $bitmap.UriSource = New-Object System.Uri($Path, [System.UriKind]::Absolute)
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
}

$script:Frames = @{}
foreach ($slug in $script:SkinSlugs) {
    $frameDir = Join-Path $skinsPath (Join-Path $slug 'frames')
    $frameList = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $frameDir -Filter '*.png' -File | Sort-Object Name)) {
        $frameList += Import-WpfBitmap -Path $file.FullName
    }
    $script:Frames[$slug] = $frameList
}

$script:SkinIndex = 0
$script:SavedState = $null
if (Test-Path -LiteralPath $script:StatePath -PathType Leaf) {
    try {
        $script:SavedState = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
        if ($null -ne $script:SavedState.skinIndex) {
            $script:SkinIndex = [math]::Max(0, [math]::Min($script:SkinSlugs.Count - 1, [int]$script:SavedState.skinIndex))
        }
    }
    catch { Write-PetLog ('State load: ' + $_.Exception.Message) }
}

$window = New-Object System.Windows.Window
$window.Title = 'VS Code Pet'
$window.Width = [double]$config.windowWidth
$window.Height = [double]$config.windowHeight
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = [bool]$config.alwaysOnTop
$window.ShowInTaskbar = $false
$window.ShowActivated = $false
$window.SizeToContent = [System.Windows.SizeToContent]::Manual
$window.Add_SourceInitialized({
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
    [CR7PetNative.VSCodeBridge]::MakeNoActivate($helper.Handle)
})

$root = New-Object System.Windows.Controls.Grid
$root.Background = [System.Windows.Media.Brushes]::Transparent
$root.Cursor = [System.Windows.Input.Cursors]::Hand
$root.ToolTip = 'Click: submit the focused Claude/Codex prompt  |  Double-click: open VS Code'
$window.Content = $root

$petImage = New-Object System.Windows.Controls.Image
$petImage.Width = [double]$config.windowWidth
$petImage.Height = 420
$petImage.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$petImage.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
$petImage.Stretch = [System.Windows.Media.Stretch]::Uniform
$petImage.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.84)
$root.Children.Add($petImage) | Out-Null

$scaleTransform = New-Object System.Windows.Media.ScaleTransform(1.0, 1.0)
$rotateTransform = New-Object System.Windows.Media.RotateTransform(0.0)
$translateTransform = New-Object System.Windows.Media.TranslateTransform(0.0, 0.0)
$transformGroup = New-Object System.Windows.Media.TransformGroup
$transformGroup.Children.Add($scaleTransform)
$transformGroup.Children.Add($rotateTransform)
$transformGroup.Children.Add($translateTransform)
$petImage.RenderTransform = $transformGroup

$bubble = New-Object System.Windows.Controls.Border
$bubble.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(247, 15, 18, 26))
$bubble.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(239, 184, 64))
$bubble.BorderThickness = New-Object System.Windows.Thickness(1.25)
$bubble.CornerRadius = New-Object System.Windows.CornerRadius(18)
$bubble.Padding = New-Object System.Windows.Thickness(12, 10, 14, 10)
$bubble.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$bubble.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
$bubble.Margin = New-Object System.Windows.Thickness(8, 6, 8, 0)
$bubble.MinWidth = 238
$bubble.MaxWidth = 304
$bubble.SnapsToDevicePixels = $true
$bubble.IsHitTestVisible = $false
$bubble.Visibility = [System.Windows.Visibility]::Collapsed

$bubbleShadow = New-Object System.Windows.Media.Effects.DropShadowEffect
$bubbleShadow.Color = [System.Windows.Media.Color]::FromRgb(0, 0, 0)
$bubbleShadow.BlurRadius = 18
$bubbleShadow.Direction = 270
$bubbleShadow.ShadowDepth = 4
$bubbleShadow.Opacity = 0.42
$bubble.Effect = $bubbleShadow

$bubbleGrid = New-Object System.Windows.Controls.Grid
$railColumn = New-Object System.Windows.Controls.ColumnDefinition
$railColumn.Width = New-Object System.Windows.GridLength(5)
$iconColumn = New-Object System.Windows.Controls.ColumnDefinition
$iconColumn.Width = New-Object System.Windows.GridLength(42)
$copyColumn = New-Object System.Windows.Controls.ColumnDefinition
$copyColumn.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$bubbleGrid.ColumnDefinitions.Add($railColumn)
$bubbleGrid.ColumnDefinitions.Add($iconColumn)
$bubbleGrid.ColumnDefinitions.Add($copyColumn)

$bubbleRail = New-Object System.Windows.Controls.Border
$bubbleRail.Width = 4
$bubbleRail.CornerRadius = New-Object System.Windows.CornerRadius(2)
$bubbleRail.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
$bubbleRail.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
[System.Windows.Controls.Grid]::SetColumn($bubbleRail, 0)
$bubbleGrid.Children.Add($bubbleRail) | Out-Null

$bubbleIconShell = New-Object System.Windows.Controls.Border
$bubbleIconShell.Width = 30
$bubbleIconShell.Height = 30
$bubbleIconShell.CornerRadius = New-Object System.Windows.CornerRadius(15)
$bubbleIconShell.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$bubbleIconShell.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
[System.Windows.Controls.Grid]::SetColumn($bubbleIconShell, 1)

$bubbleIcon = New-Object System.Windows.Controls.TextBlock
$bubbleIcon.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Semibold')
$bubbleIcon.FontSize = 14
$bubbleIcon.FontWeight = [System.Windows.FontWeights]::Bold
$bubbleIcon.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$bubbleIcon.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
$bubbleIcon.TextAlignment = [System.Windows.TextAlignment]::Center
$bubbleIconShell.Child = $bubbleIcon
$bubbleGrid.Children.Add($bubbleIconShell) | Out-Null

$bubbleCopy = New-Object System.Windows.Controls.StackPanel
$bubbleCopy.Orientation = [System.Windows.Controls.Orientation]::Vertical
$bubbleCopy.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
[System.Windows.Controls.Grid]::SetColumn($bubbleCopy, 2)

$bubbleLabel = New-Object System.Windows.Controls.TextBlock
$bubbleLabel.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(168, 174, 190))
$bubbleLabel.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Semibold')
$bubbleLabel.FontSize = 9
$bubbleLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
$bubbleLabel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 2)
$bubbleCopy.Children.Add($bubbleLabel) | Out-Null

$bubbleText = New-Object System.Windows.Controls.TextBlock
$bubbleText.Foreground = [System.Windows.Media.Brushes]::White
$bubbleText.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Semibold')
$bubbleText.FontSize = 12.5
$bubbleText.FontWeight = [System.Windows.FontWeights]::SemiBold
$bubbleText.TextAlignment = [System.Windows.TextAlignment]::Left
$bubbleText.TextWrapping = [System.Windows.TextWrapping]::Wrap
$bubbleCopy.Children.Add($bubbleText) | Out-Null

$bubbleSubtitle = New-Object System.Windows.Controls.TextBlock
$bubbleSubtitle.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(188, 193, 207))
$bubbleSubtitle.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
$bubbleSubtitle.FontSize = 10
$bubbleSubtitle.TextAlignment = [System.Windows.TextAlignment]::Left
$bubbleSubtitle.TextWrapping = [System.Windows.TextWrapping]::Wrap
$bubbleSubtitle.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
$bubbleSubtitle.Visibility = [System.Windows.Visibility]::Collapsed
$bubbleCopy.Children.Add($bubbleSubtitle) | Out-Null

$bubbleGrid.Children.Add($bubbleCopy) | Out-Null
$bubble.Child = $bubbleGrid
$root.Children.Add($bubble) | Out-Null
[System.Windows.Controls.Panel]::SetZIndex($bubble, 20)

$script:BubblePersistent = $false
$bubbleTimer = New-Object System.Windows.Threading.DispatcherTimer
$bubbleTimer.Add_Tick({
    $bubbleTimer.Stop()
    if ($script:BubblePersistent) { return }
    $bubble.Visibility = [System.Windows.Visibility]::Collapsed
})

function Show-PetMessage {
    param(
        [string]$Text,
        [int]$Milliseconds = 1300,
        [ValidateSet('Gold', 'Success', 'Info', 'Warning', 'Error', 'Claude', 'Codex')]
        [string]$Tone = 'Gold',
        [string]$Subtitle = '',
        [switch]$Persistent
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $visual = switch ($Tone) {
        'Success' { @{ Accent = [System.Windows.Media.Color]::FromRgb(56, 211, 159); Surface = [System.Windows.Media.Color]::FromArgb(248, 12, 26, 25); Label = 'COMPLETED'; Icon = [char]0x2713 } }
        'Info' { @{ Accent = [System.Windows.Media.Color]::FromRgb(103, 164, 255); Surface = [System.Windows.Media.Color]::FromArgb(248, 13, 20, 33); Label = 'VS CODE PET'; Icon = 'i' } }
        'Warning' { @{ Accent = [System.Windows.Media.Color]::FromRgb(239, 184, 64); Surface = [System.Windows.Media.Color]::FromArgb(248, 29, 24, 13); Label = 'ATTENTION'; Icon = '!' } }
        'Error' { @{ Accent = [System.Windows.Media.Color]::FromRgb(255, 98, 105); Surface = [System.Windows.Media.Color]::FromArgb(248, 32, 14, 20); Label = 'BLOCKED'; Icon = [char]0x00D7 } }
        'Claude' { @{ Accent = [System.Windows.Media.Color]::FromRgb(224, 128, 92); Surface = [System.Windows.Media.Color]::FromArgb(250, 31, 20, 17); Label = 'CLAUDE  /  ACTION REQUIRED'; Icon = 'C' } }
        'Codex' { @{ Accent = [System.Windows.Media.Color]::FromRgb(66, 207, 164); Surface = [System.Windows.Media.Color]::FromArgb(248, 11, 27, 25); Label = 'CODEX'; Icon = 'C' } }
        default { @{ Accent = [System.Windows.Media.Color]::FromRgb(239, 184, 64); Surface = [System.Windows.Media.Color]::FromArgb(247, 15, 18, 26); Label = 'VS CODE PET'; Icon = '7' } }
    }
    $accentBrush = New-Object System.Windows.Media.SolidColorBrush($visual.Accent)
    $iconSurface = [System.Windows.Media.Color]::FromArgb(46, $visual.Accent.R, $visual.Accent.G, $visual.Accent.B)
    $bubble.Background = New-Object System.Windows.Media.SolidColorBrush($visual.Surface)
    $bubble.BorderBrush = $accentBrush
    $bubbleRail.Background = $accentBrush
    $bubbleIcon.Foreground = $accentBrush
    $bubbleIconShell.Background = New-Object System.Windows.Media.SolidColorBrush($iconSurface)
    $bubbleIcon.Text = [string]$visual.Icon
    $bubbleLabel.Text = [string]$visual.Label
    $bubbleText.Text = $Text
    $bubbleSubtitle.Text = $Subtitle
    $bubbleSubtitle.Visibility = if ([string]::IsNullOrWhiteSpace($Subtitle)) {
        [System.Windows.Visibility]::Collapsed
    }
    else {
        [System.Windows.Visibility]::Visible
    }
    $bubble.Visibility = [System.Windows.Visibility]::Visible
    $bubbleTimer.Stop()
    $script:BubblePersistent = [bool]$Persistent
    if (-not $Persistent) {
        $bubbleTimer.Interval = [TimeSpan]::FromMilliseconds($Milliseconds)
        $bubbleTimer.Start()
    }
}

function Hide-PetMessage {
    $script:BubblePersistent = $false
    $bubbleTimer.Stop()
    $bubble.Visibility = [System.Windows.Visibility]::Collapsed
}

$script:Animations = @{
    rest = @{
        Frames = @(0)
        Durations = @(60000)
        Priority = 0
        Loop = $true
        Message = ''
    }
    idle = @{
        Frames = @(0, 0, 0, 0, 0)
        Durations = @(260, 260, 260, 260, 340)
        Priority = 0
        Loop = $false
        Message = ''
    }
    bicycle = @{
        Frames = @(5, 6, 7, 8, 9)
        Durations = @(190, 150, 180, 230, 350)
        Priority = 10
        Loop = $false
        Message = 'OVERHEAD!'
    }
    siu = @{
        Frames = @(10, 11, 12, 13, 14)
        Durations = @(300, 170, 330, 190, 520)
        Priority = 10
        Loop = $false
        Message = 'ME. HERE. SIUUU!'
    }
    calma = @{
        Frames = @(15, 16, 15, 16, 16)
        Durations = @(230, 260, 230, 300, 420)
        Priority = 7
        Loop = $false
        Message = 'CALMA.'
    }
    meditate = @{
        Frames = @(17, 18, 19, 18, 19)
        Durations = @(220, 300, 440, 300, 520)
        Priority = 7
        Loop = $false
        Message = 'FOCUS.'
    }
    shirt = @{
        Frames = @(20, 21, 22, 23, 24)
        Durations = @(190, 190, 230, 520, 500)
        Priority = 9
        Loop = $false
        Message = 'MAXIMUM!'
    }
}

$script:Motion = @{
    rest = @(
        @{ ScaleX = 1.000; ScaleY = 1.000; X = 0; Y = 0; Rotation = 0.0 }
    )
    idle = @(
        @{ ScaleX = 1.000; ScaleY = 1.000; X = -1.5; Y = 0; Rotation = -0.35 },
        @{ ScaleX = 1.003; ScaleY = 1.004; X = 1.5; Y = -0.5; Rotation = 0.35 },
        @{ ScaleX = 1.000; ScaleY = 1.000; X = -1.0; Y = 0; Rotation = -0.25 },
        @{ ScaleX = 1.002; ScaleY = 1.003; X = 1.0; Y = -0.4; Rotation = 0.25 },
        @{ ScaleX = 1.000; ScaleY = 1.000; X = 0; Y = 0; Rotation = 0.0 }
    )
    bicycle = @(
        @{ ScaleX = 0.97; ScaleY = 1.03; Y = 3; Rotation = 0 },
        @{ ScaleX = 1.04; ScaleY = 0.96; Y = -12; Rotation = -5 },
        @{ ScaleX = 1.00; ScaleY = 1.00; Y = -30; Rotation = -10 },
        @{ ScaleX = 1.05; ScaleY = 0.96; Y = -36; Rotation = 7 },
        @{ ScaleX = 1.03; ScaleY = 0.93; Y = 4; Rotation = 0 }
    )
    siu = @(
        @{ ScaleX = 1.00; ScaleY = 1.00; Y = 0; Rotation = -1 },
        @{ ScaleX = 1.02; ScaleY = 0.98; Y = 1; Rotation = 1 },
        @{ ScaleX = 0.98; ScaleY = 1.02; Y = 0; Rotation = 0 },
        @{ ScaleX = 1.02; ScaleY = 0.98; Y = -38; Rotation = 6 },
        @{ ScaleX = 1.06; ScaleY = 0.92; Y = 3; Rotation = 0 }
    )
    calma = @(
        @{ ScaleX = 1.00; ScaleY = 1.00; Y = 0; Rotation = -1 },
        @{ ScaleX = 1.02; ScaleY = 0.98; Y = 1; Rotation = 1 },
        @{ ScaleX = 1.00; ScaleY = 1.00; Y = 0; Rotation = -1 },
        @{ ScaleX = 1.02; ScaleY = 0.98; Y = 1; Rotation = 1 },
        @{ ScaleX = 1.00; ScaleY = 1.00; Y = 0; Rotation = 0 }
    )
    meditate = @(
        @{ ScaleX = 1.00; ScaleY = 1.00; Y = 0; Rotation = 0 },
        @{ ScaleX = 1.01; ScaleY = 1.01; Y = -1; Rotation = -0.5 },
        @{ ScaleX = 1.00; ScaleY = 1.015; Y = -2; Rotation = 0.5 },
        @{ ScaleX = 1.01; ScaleY = 1.01; Y = -1; Rotation = -0.4 },
        @{ ScaleX = 1.00; ScaleY = 1.015; Y = -2; Rotation = 0.3 }
    )
    shirt = @(
        @{ ScaleX = 0.98; ScaleY = 1.03; Y = 2; Rotation = 0 },
        @{ ScaleX = 1.02; ScaleY = 1.00; Y = -2; Rotation = -1 },
        @{ ScaleX = 1.04; ScaleY = 0.98; Y = -5; Rotation = 1 },
        @{ ScaleX = 1.08; ScaleY = 0.94; Y = 2; Rotation = 0 },
        @{ ScaleX = 1.02; ScaleY = 1.00; Y = 0; Rotation = 0 }
    )
}

$script:CurrentAnimation = 'rest'
$script:AnimationStep = -1
$script:CurrentPriority = 0
$script:FrameDeadline = [DateTime]::MinValue

function Start-PropertyAnimation {
    param(
        [System.Windows.Media.Animation.IAnimatable]$Target,
        [System.Windows.DependencyProperty]$Property,
        [double]$To,
        [int]$Milliseconds
    )
    $animation = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animation.To = $To
    $animation.Duration = [TimeSpan]::FromMilliseconds([math]::Max(45, [math]::Min(120, $Milliseconds * 0.62)))
    $ease = New-Object System.Windows.Media.Animation.QuadraticEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $animation.EasingFunction = $ease
    $Target.BeginAnimation($Property, $animation)
}

function Set-PetFrame {
    param([int]$FrameIndex, [int]$StepDuration)
    $slug = $script:SkinSlugs[$script:SkinIndex]
    $petImage.Source = $script:Frames[$slug][$FrameIndex]
    $motion = $script:Motion[$script:CurrentAnimation][$script:AnimationStep]
    $motionX = 0.0
    if ($motion.ContainsKey('X')) { $motionX = [double]$motion.X }
    Start-PropertyAnimation $scaleTransform ([System.Windows.Media.ScaleTransform]::ScaleXProperty) ([double]$motion.ScaleX) $StepDuration
    Start-PropertyAnimation $scaleTransform ([System.Windows.Media.ScaleTransform]::ScaleYProperty) ([double]$motion.ScaleY) $StepDuration
    Start-PropertyAnimation $rotateTransform ([System.Windows.Media.RotateTransform]::AngleProperty) ([double]$motion.Rotation) $StepDuration
    Start-PropertyAnimation $translateTransform ([System.Windows.Media.TranslateTransform]::XProperty) $motionX $StepDuration
    Start-PropertyAnimation $translateTransform ([System.Windows.Media.TranslateTransform]::YProperty) ([double]$motion.Y) $StepDuration
}

function Start-PetAnimation {
    param([string]$Name, [switch]$Force)
    $spec = $script:Animations[$Name]
    if (-not $Force -and $script:CurrentPriority -gt [int]$spec.Priority) { return }
    $script:CurrentAnimation = $Name
    $script:AnimationStep = -1
    $script:CurrentPriority = [int]$spec.Priority
    $script:FrameDeadline = [DateTime]::MinValue
    if (-not [string]::IsNullOrWhiteSpace([string]$spec.Message)) {
        Show-PetMessage -Text ([string]$spec.Message) -Milliseconds 1250
    }
}

function Update-PetAnimation {
    if ((Get-Date) -lt $script:FrameDeadline) { return }
    $spec = $script:Animations[$script:CurrentAnimation]
    $script:AnimationStep++
    if ($script:AnimationStep -ge $spec.Frames.Count) {
        if ([bool]$spec.Loop) {
            $script:AnimationStep = 0
        }
        else {
            Start-PetAnimation -Name 'rest' -Force
            $spec = $script:Animations['rest']
            $script:AnimationStep = 0
        }
    }
    $duration = [int]$spec.Durations[$script:AnimationStep]
    Set-PetFrame -FrameIndex ([int]$spec.Frames[$script:AnimationStep]) -StepDuration $duration
    $script:FrameDeadline = (Get-Date).AddMilliseconds($duration)
}

function Switch-PetSkin {
    $script:SkinIndex = ($script:SkinIndex + 1) % $script:SkinSlugs.Count
    $spec = $script:Animations[$script:CurrentAnimation]
    $safeStep = [math]::Max(0, [math]::Min($script:AnimationStep, $spec.Frames.Count - 1))
    $slug = $script:SkinSlugs[$script:SkinIndex]
    $petImage.Source = $script:Frames[$slug][[int]$spec.Frames[$safeStep]]
    Show-PetMessage -Text ($script:SkinNames[$script:SkinIndex] + '  |  7') -Milliseconds 1500
    Write-PetLog ('Skin switched: ' + $script:SkinNames[$script:SkinIndex])
}

$animationTimer = New-Object System.Windows.Threading.DispatcherTimer
$animationTimer.Interval = [TimeSpan]::FromMilliseconds([int]$config.animationTickMs)
$animationTimer.Add_Tick({ Update-PetAnimation })

$script:LastHookCounter = 0
$script:LastSiuCounter = 0
$script:LastBicycleCounter = 0
$hookTimer = New-Object System.Windows.Threading.DispatcherTimer
$hookTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$hookTimer.Add_Tick({
    $counter = [CR7PetNative.KeyboardHook]::SwitchCounter
    if ($counter -ne $script:LastHookCounter) {
        $script:LastHookCounter = $counter
        Switch-PetSkin
    }
    $siuCounter = [CR7PetNative.KeyboardHook]::SiuCounter
    if ($siuCounter -ne $script:LastSiuCounter) {
        $script:LastSiuCounter = $siuCounter
        Start-PetAnimation -Name 'siu' -Force
        Write-PetLog 'Shortcut Enter: SIU'
    }
    $bicycleCounter = [CR7PetNative.KeyboardHook]::BicycleCounter
    if ($bicycleCounter -ne $script:LastBicycleCounter) {
        $script:LastBicycleCounter = $bicycleCounter
        Start-PetAnimation -Name 'bicycle' -Force
        Write-PetLog 'Shortcut Backspace: bicycle'
    }
})

$script:LastVolume = $null
$script:LastMuted = $null
$volumeTimer = New-Object System.Windows.Threading.DispatcherTimer
$volumeTimer.Interval = [TimeSpan]::FromMilliseconds([int]$config.volumePollMs)
$volumeTimer.Add_Tick({
    try {
        $snapshot = [CR7PetNative.Sensors]::ReadAudio()
        if ($null -ne $script:LastVolume) {
            $delta = $snapshot.Volume - $script:LastVolume
            if ($snapshot.Muted -and -not $script:LastMuted) {
                Start-PetAnimation -Name 'bicycle'
            }
            elseif (-not $snapshot.Muted -and $delta -le -0.006) {
                Start-PetAnimation -Name 'calma'
            }
            elseif (-not $snapshot.Muted -and $delta -ge 0.006) {
                Start-PetAnimation -Name 'meditate'
            }
        }
        $script:LastVolume = $snapshot.Volume
        $script:LastMuted = $snapshot.Muted
    }
    catch { Write-PetLog ('Audio sensor: ' + $_.Exception.Message) }
})

$script:LastBrightness = $null
$brightnessTimer = New-Object System.Windows.Threading.DispatcherTimer
$brightnessTimer.Interval = [TimeSpan]::FromMilliseconds([int]$config.brightnessPollMs)
$brightnessTimer.Add_Tick({
    try {
        $brightness = [CR7PetNative.Sensors]::ReadBrightness()
        if ($brightness -ge 0) {
            if ($null -ne $script:LastBrightness -and $brightness -eq 100 -and $script:LastBrightness -lt 100) {
                Start-PetAnimation -Name 'shirt'
            }
            $script:LastBrightness = $brightness
        }
    }
    catch { Write-PetLog ('Brightness sensor: ' + $_.Exception.Message) }
})

$script:CodexWasRunning = $false
$codexTimer = New-Object System.Windows.Threading.DispatcherTimer
$codexTimer.Interval = [TimeSpan]::FromMilliseconds([int]$config.codexPollMs)
$codexTimer.Add_Tick({
    if (-not [bool]$config.triggerOnCodexOpen) { return }
    try {
        $running = @(Get-Process -Name 'ChatGPT', 'codex' -ErrorAction SilentlyContinue).Count -gt 0
        if ($running -and -not $script:CodexWasRunning) {
            Start-PetAnimation -Name 'bicycle'
        }
        $script:CodexWasRunning = $running
    }
    catch { Write-PetLog ('Codex sensor: ' + $_.Exception.Message) }
})

$script:CodexControlEnter = $false
$script:ClaudeControlEnter = $false
$script:ClaudeUsesTerminal = $false
$vsCodeSettingsPath = Join-Path $env:APPDATA 'Code\User\settings.json'
if (Test-Path -LiteralPath $vsCodeSettingsPath -PathType Leaf) {
    try {
        $vsCodeSettingsText = Get-Content -LiteralPath $vsCodeSettingsPath -Raw
        if ($vsCodeSettingsText -match '"chatgpt\.composerEnterBehavior"\s*:\s*"(?<value>[^"]+)"') {
            $script:CodexControlEnter = $Matches.value -ne 'enter'
        }
        if ($vsCodeSettingsText -match '"claudeCode\.useTerminal"\s*:\s*(?<value>true|false)') {
            $script:ClaudeUsesTerminal = $Matches.value -eq 'true'
        }
        if ($vsCodeSettingsText -match '"claudeCode\.useCtrlEnterToSend"\s*:\s*(?<value>true|false)') {
            $script:ClaudeControlEnter = $Matches.value -eq 'true'
        }
        if ($script:ClaudeUsesTerminal) { $script:ClaudeControlEnter = $false }
    }
    catch { Write-PetLog ('VS Code settings: ' + $_.Exception.Message) }
}

$script:LastVSCodeInfo = $null
$script:LastVSCodeSeen = [DateTime]::MinValue

function Update-VSCodeFocusMemory {
    try {
        $info = [CR7PetNative.VSCodeBridge]::GetForegroundInfo()
        if ($null -ne $info -and $info.ProcessName -ieq 'Code') {
            $script:LastVSCodeInfo = $info
            $script:LastVSCodeSeen = Get-Date
        }
    }
    catch { }
}

$focusTimer = New-Object System.Windows.Threading.DispatcherTimer
$focusTimer.Interval = [TimeSpan]::FromMilliseconds(90)
$focusTimer.Add_Tick({ Update-VSCodeFocusMemory })

function Get-VSCodeForeground {
    param([switch]$AllowRecentRestore)

    $info = [CR7PetNative.VSCodeBridge]::GetForegroundInfo()
    if ($null -ne $info -and $info.ProcessName -ieq 'Code') { return $info }

    if (
        $AllowRecentRestore -and
        $null -ne $script:LastVSCodeInfo -and
        ((Get-Date) - $script:LastVSCodeSeen).TotalMilliseconds -le 3200
    ) {
        if ([CR7PetNative.VSCodeBridge]::RestoreWindow($script:LastVSCodeInfo.Handle)) {
            Start-Sleep -Milliseconds 90
            $info = [CR7PetNative.VSCodeBridge]::GetForegroundInfo()
            if ($null -ne $info -and $info.ProcessName -ieq 'Code') { return $info }
        }
    }
    return $null
}

function Get-FocusedAutomationContext {
    $names = New-Object System.Collections.Generic.List[string]
    $automationIds = New-Object System.Collections.Generic.List[string]
    $classNames = New-Object System.Collections.Generic.List[string]
    $controlType = ''
    $processName = ''
    try {
        $element = [System.Windows.Automation.AutomationElement]::FocusedElement
        if ($null -ne $element) {
            $controlType = [string]$element.Current.ControlType.ProgrammaticName
            try {
                $focusProcess = Get-Process -Id ([int]$element.Current.ProcessId) -ErrorAction Stop
                $processName = $focusProcess.ProcessName
            }
            catch { }
        }
        for ($depth = 0; $depth -lt 12 -and $null -ne $element; $depth++) {
            if (-not [string]::IsNullOrWhiteSpace([string]$element.Current.Name)) {
                $names.Add([string]$element.Current.Name)
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$element.Current.AutomationId)) {
                $automationIds.Add([string]$element.Current.AutomationId)
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$element.Current.ClassName)) {
                $classNames.Add([string]$element.Current.ClassName)
            }
            $element = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($element)
        }
    }
    catch { }
    return [pscustomobject]@{
        Names = @($names)
        AutomationIds = @($automationIds)
        ClassNames = @($classNames)
        ControlType = $controlType
        ProcessName = $processName
    }
}

$script:ConfirmationSemanticPattern = '(?i)permission\s*request|permissionRequest|approval\s*required|allow once|allow always|yes,?\s+allow|approve|confirmation|confirm action|press enter to confirm|do you want to proceed|request to run|run command|accept proposed|reject proposed'

function Get-ClaudeConfirmationSnapshot {
    $info = [CR7PetNative.VSCodeBridge]::GetForegroundInfo()
    if ($null -eq $info -or $info.ProcessName -ine 'Code') {
        return [pscustomobject]@{ Observed = $false; Active = $false; Detail = '' }
    }

    $automation = Get-FocusedAutomationContext
    if (-not [string]::IsNullOrWhiteSpace($automation.ProcessName) -and $automation.ProcessName -ine 'Code') {
        return [pscustomobject]@{ Observed = $true; Active = $false; Detail = $automation.ControlType }
    }

    $automationSemantic = @(
        $automation.Names
        $automation.AutomationIds
        $automation.ClassNames
    ) -join ' | '
    $semantic = ([string]$info.Title) + ' | ' + $automationSemantic
    $claudeEvidence = ([string]$info.Title) -match '(?i)\[\s*Claude Code\s*\]' -or $semantic -match '(?i)\bclaude(?: code)?\b'
    $confirmationContainer = $automationSemantic -match '(?i)permissionRequest|permission[-_ ]?request|confirmation|approval'
    $actionControl = $automation.ControlType -match 'Button|CheckBox|RadioButton|MenuItem|ListItem'
    $confirmationText = $semantic -match $script:ConfirmationSemanticPattern
    $active = $claudeEvidence -and ($confirmationContainer -or ($actionControl -and $confirmationText))

    return [pscustomobject]@{
        Observed = $true
        Active = [bool]$active
        Detail = $automation.ControlType
    }
}

function Get-AISubmitContext {
    param(
        [ValidateSet('Auto', 'Claude', 'Codex')]
        [string]$PreferredProvider = 'Auto',
        [switch]$AllowRecentRestore
    )

    $info = Get-VSCodeForeground -AllowRecentRestore:$AllowRecentRestore
    if ($null -eq $info) {
        return [pscustomobject]@{ Ready = $false; Status = 'NotVSCode'; Provider = ''; ControlEnter = $false; Detail = '' }
    }

    $automation = Get-FocusedAutomationContext
    if (-not [string]::IsNullOrWhiteSpace($automation.ProcessName) -and $automation.ProcessName -ine 'Code') {
        return [pscustomobject]@{ Ready = $false; Status = 'NoAIFocus'; Provider = ''; ControlEnter = $false; Detail = $automation.ControlType }
    }

    $automationSemantic = @(
        $automation.Names
        $automation.AutomationIds
        $automation.ClassNames
    ) -join ' | '
    $semantic = ([string]$info.Title) + ' | ' + $automationSemantic

    $buttonLike = $automation.ControlType -match 'Button|CheckBox|RadioButton|MenuItem|ListItem|Hyperlink|Window'
    $dangerousText = $semantic -match $script:ConfirmationSemanticPattern
    if ($buttonLike -or $dangerousText) {
        return [pscustomobject]@{ Ready = $false; Status = 'ConfirmationBlocked'; Provider = ''; ControlEnter = $false; Detail = $automation.ControlType }
    }

    $inputEvidence = $automation.ControlType -match 'Edit' -or $automationSemantic -match '(?i)composer|prompt|chat input|textarea|message input'
    $claudeTerminalTitle = ([string]$info.Title) -match '(?i)\[\s*Claude Code\s*\]'
    $hasClaude = $claudeTerminalTitle -or (($automationSemantic -match '(?i)\bclaude(?: code)?\b') -and $inputEvidence)
    $hasCodex = ($automationSemantic -match '(?i)\bcodex\b|\bchatgpt\b|openai-codex') -and $inputEvidence
    $provider = switch ($PreferredProvider) {
        'Claude' { if ($hasClaude) { 'Claude' } else { '' } }
        'Codex' { if ($hasCodex) { 'Codex' } else { '' } }
        default {
            if ($hasClaude) { 'Claude' }
            elseif ($hasCodex) { 'Codex' }
            else { '' }
        }
    }

    if ([string]::IsNullOrWhiteSpace($provider)) {
        return [pscustomobject]@{ Ready = $false; Status = 'NoAIFocus'; Provider = ''; ControlEnter = $false; Detail = $automation.ControlType }
    }

    $controlEnter = if ($provider -eq 'Claude') { $script:ClaudeControlEnter } else { $script:CodexControlEnter }
    return [pscustomobject]@{
        Ready = $true
        Status = 'Ready'
        Provider = $provider
        ControlEnter = [bool]$controlEnter
        Detail = $automation.ControlType
    }
}

$script:ClaudeConfirmationActive = $false
$script:ClaudeConfirmationMissingPolls = 0
$script:ClaudeConfirmationLastPulse = [DateTime]::MinValue
$script:ClaudeConfirmationMessage = 'CLAUDE NEEDS CONFIRMATION'
$script:ClaudeConfirmationPulseMs = 2800

function Show-ClaudeConfirmationCard {
    Show-PetMessage `
        -Text $script:ClaudeConfirmationMessage `
        -Tone 'Claude' `
        -Subtitle 'Review the request in VS Code' `
        -Persistent
}

function Invoke-ClaudeConfirmationPulse {
    Start-PetAnimation -Name 'calma' -Force
    Show-ClaudeConfirmationCard
    $script:ClaudeConfirmationLastPulse = Get-Date
}

function Enter-ClaudeConfirmationState {
    param([switch]$ForcePulse)

    $wasActive = $script:ClaudeConfirmationActive
    $script:ClaudeConfirmationActive = $true
    $script:ClaudeConfirmationMissingPolls = 0
    $pulseDue = ((Get-Date) - $script:ClaudeConfirmationLastPulse).TotalMilliseconds -ge $script:ClaudeConfirmationPulseMs

    if (-not $wasActive -or $ForcePulse -or $pulseDue) {
        Invoke-ClaudeConfirmationPulse
    }
    elseif (-not $script:BubblePersistent -or $bubbleText.Text -ne $script:ClaudeConfirmationMessage) {
        Show-ClaudeConfirmationCard
    }

    if (-not $wasActive) {
        Write-PetLog 'Claude confirmation detected: persistent Calma state entered.'
    }
}

function Exit-ClaudeConfirmationState {
    if (-not $script:ClaudeConfirmationActive) { return }
    $script:ClaudeConfirmationActive = $false
    $script:ClaudeConfirmationMissingPolls = 0
    $script:BubblePersistent = $false
    Show-PetMessage `
        -Text 'CLAUDE CONFIRMATION CLOSED' `
        -Milliseconds 1550 `
        -Tone 'Success' `
        -Subtitle 'The action request is no longer active'
    Write-PetLog 'Claude confirmation cleared: persistent Calma state exited.'
}

$confirmationTimer = New-Object System.Windows.Threading.DispatcherTimer
$confirmationTimer.Interval = [TimeSpan]::FromMilliseconds(420)
$confirmationTimer.Add_Tick({
    try {
        $snapshot = Get-ClaudeConfirmationSnapshot
        if ($snapshot.Active) {
            Enter-ClaudeConfirmationState
            return
        }

        if (-not $script:ClaudeConfirmationActive) { return }

        if ($snapshot.Observed) {
            $script:ClaudeConfirmationMissingPolls++
            if ($script:ClaudeConfirmationMissingPolls -ge 3) {
                Exit-ClaudeConfirmationState
                return
            }
        }
        elseif (@(Get-Process -Name 'Code' -ErrorAction SilentlyContinue).Count -eq 0) {
            Exit-ClaudeConfirmationState
            return
        }

        Enter-ClaudeConfirmationState
    }
    catch {
        Write-PetLog ('Claude confirmation sensor: ' + $_.Exception.Message)
    }
})

function Submit-FocusedAIPrompt {
    param(
        [ValidateSet('Auto', 'Claude', 'Codex')]
        [string]$PreferredProvider = 'Auto',
        [switch]$ShowInactiveMessage
    )

    $context = Get-AISubmitContext -PreferredProvider $PreferredProvider -AllowRecentRestore
    if (-not $context.Ready) {
        switch ($context.Status) {
            'NotVSCode' {
                if ($ShowInactiveMessage) { Show-PetMessage -Text 'VS CODE NOT ACTIVE' -Milliseconds 1450 -Tone 'Warning' }
            }
            'ConfirmationBlocked' {
                $confirmationSnapshot = Get-ClaudeConfirmationSnapshot
                if ($confirmationSnapshot.Active) {
                    Enter-ClaudeConfirmationState -ForcePulse
                }
                else {
                    Show-PetMessage `
                        -Text 'CONFIRMATION BLOCKED' `
                        -Milliseconds 1700 `
                        -Tone 'Error' `
                        -Subtitle 'Return to a Claude or Codex prompt'
                }
                Write-PetLog ('AI submit blocked: confirmation control ' + $context.Detail)
            }
            default {
                Show-PetMessage -Text 'FOCUS CLAUDE OR CODEX' -Milliseconds 1650 -Tone 'Warning'
                Write-PetLog ('AI submit blocked: no verified AI input ' + $context.Detail)
            }
        }
        return $context.Status
    }

    $foregroundCheck = [CR7PetNative.VSCodeBridge]::GetForegroundInfo()
    if ($null -eq $foregroundCheck -or $foregroundCheck.ProcessName -ine 'Code') {
        Show-PetMessage -Text 'FOCUS CHANGED' -Milliseconds 1450 -Tone 'Error'
        Write-PetLog 'AI submit cancelled: foreground changed before key dispatch.'
        return 'FocusChanged'
    }

    if (-not [CR7PetNative.VSCodeBridge]::SendSubmitKey([bool]$context.ControlEnter)) {
        Show-PetMessage -Text 'SUBMIT FAILED' -Milliseconds 1500 -Tone 'Error'
        Write-PetLog ('AI submit failed: SendInput provider=' + $context.Provider)
        return 'Failed'
    }

    Start-PetAnimation -Name 'siu' -Force
    Show-PetMessage -Text ('SENT  /  ' + $context.Provider.ToUpperInvariant()) -Milliseconds 1650 -Tone $context.Provider
    Write-PetLog ('AI prompt submitted: provider={0} key={1}' -f $context.Provider, $(if ($context.ControlEnter) { 'Ctrl+Enter' } else { 'Enter' }))
    return 'Sent'
}

function Open-VSCodeAndCelebrate {
    Start-PetAnimation -Name 'shirt' -Force
    $existingVSCode = @(Get-Process -Name 'Code' -ErrorAction SilentlyContinue).Count -gt 0
    if ($existingVSCode) {
        Show-PetMessage -Text 'VS CODE IS OPEN' -Milliseconds 1500
        Write-PetLog 'Double-click: VS Code was already running; no new launch.'
        return
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),
        'C:\Program Files\Microsoft VS Code\Code.exe',
        'C:\Program Files (x86)\Microsoft VS Code\Code.exe'
    )
    $codePath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $codePath) {
        $codeCommand = Get-Command code -ErrorAction SilentlyContinue
        if ($codeCommand) { $codePath = $codeCommand.Source }
    }
    if ($codePath) {
        Show-PetMessage -Text 'OPENING VS CODE' -Milliseconds 1500
        Start-Process -FilePath $codePath
        Write-PetLog ('Double-click: opened VS Code from ' + $codePath)
    }
    else {
        Show-PetMessage -Text 'VS CODE NOT FOUND' -Milliseconds 1800
        Write-PetLog 'Double-click: VS Code was not found.'
    }
}

$menu = New-Object System.Windows.Controls.ContextMenu
$submitItem = New-Object System.Windows.Controls.MenuItem
$submitItem.Header = 'Submit Focused AI Prompt'
$submitItem.FontWeight = [System.Windows.FontWeights]::SemiBold
$submitItem.Add_Click({ Submit-FocusedAIPrompt -PreferredProvider 'Auto' -ShowInactiveMessage | Out-Null })
$menu.Items.Add($submitItem) | Out-Null

$submitClaudeItem = New-Object System.Windows.Controls.MenuItem
$submitClaudeItem.Header = 'Submit to Focused Claude'
$submitClaudeItem.Add_Click({ Submit-FocusedAIPrompt -PreferredProvider 'Claude' -ShowInactiveMessage | Out-Null })
$menu.Items.Add($submitClaudeItem) | Out-Null

$submitCodexItem = New-Object System.Windows.Controls.MenuItem
$submitCodexItem.Header = 'Submit to Focused Codex'
$submitCodexItem.Add_Click({ Submit-FocusedAIPrompt -PreferredProvider 'Codex' -ShowInactiveMessage | Out-Null })
$menu.Items.Add($submitCodexItem) | Out-Null
$menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null

$menuSpecs = @(
    @{ Header = 'Open VS Code + Shirt-Rip'; Action = { Open-VSCodeAndCelebrate } },
    @{ Header = 'Bicycle Kick'; Action = { Start-PetAnimation -Name 'bicycle' -Force } },
    @{ Header = 'Point > Ground > SIU'; Action = { Start-PetAnimation -Name 'siu' -Force } },
    @{ Header = 'Calma'; Action = { Start-PetAnimation -Name 'calma' -Force } },
    @{ Header = 'Sleeping Meditation'; Action = { Start-PetAnimation -Name 'meditate' -Force } },
    @{ Header = 'Shirt-Rip Power'; Action = { Start-PetAnimation -Name 'shirt' -Force } },
    @{ Header = 'Next Skin    7'; Action = { Switch-PetSkin } }
)
foreach ($menuSpec in $menuSpecs) {
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Header = $menuSpec.Header
    $item.Add_Click($menuSpec.Action)
    $menu.Items.Add($item) | Out-Null
}
$menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
$topItem = New-Object System.Windows.Controls.MenuItem
$topItem.Header = 'Always on Top'
$topItem.IsCheckable = $true
$topItem.IsChecked = $window.Topmost
$topItem.Add_Click({ $window.Topmost = $topItem.IsChecked })
$menu.Items.Add($topItem) | Out-Null
$resetItem = New-Object System.Windows.Controls.MenuItem
$resetItem.Header = 'Reset Position'
$resetItem.Add_Click({
    $area = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $area.Right - $window.Width - 22
    $window.Top = $area.Bottom - $window.Height - 12
})
$menu.Items.Add($resetItem) | Out-Null
$exitItem = New-Object System.Windows.Controls.MenuItem
$exitItem.Header = 'Exit VS Code Pet'
$exitItem.Add_Click({ $window.Close() })
$menu.Items.Add($exitItem) | Out-Null
$root.ContextMenu = $menu

$singleClickTimer = New-Object System.Windows.Threading.DispatcherTimer
$singleClickTimer.Interval = [TimeSpan]::FromMilliseconds(280)
$singleClickTimer.Add_Tick({
    $singleClickTimer.Stop()
    $submitResult = Submit-FocusedAIPrompt -PreferredProvider 'Auto'
    if ($submitResult -eq 'NotVSCode') {
        Start-PetAnimation -Name 'siu' -Force
    }
})

$petImage.Add_MouseEnter({
    if ($script:CurrentPriority -eq 0 -and $script:CurrentAnimation -eq 'rest') {
        Start-PetAnimation -Name 'idle'
    }
})
$petImage.Add_MouseLeave({
    if ($script:CurrentPriority -eq 0) {
        Start-PetAnimation -Name 'rest' -Force
    }
})

$window.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($eventArgs.ClickCount -ge 2) {
        $singleClickTimer.Stop()
        Open-VSCodeAndCelebrate
        return
    }
    $beforeX = $window.Left
    $beforeY = $window.Top
    try { $window.DragMove() }
    catch { }
    $distance = [math]::Abs($window.Left - $beforeX) + [math]::Abs($window.Top - $beforeY)
    if ($distance -lt 4) {
        $singleClickTimer.Stop()
        $singleClickTimer.Start()
    }
})

$area = [System.Windows.SystemParameters]::WorkArea
$window.Left = $area.Right - $window.Width - 22
$window.Top = $area.Bottom - $window.Height - 12
if ($null -ne $script:SavedState) {
    try {
        $x = [double]$script:SavedState.x
        $y = [double]$script:SavedState.y
        if ($x -ge $area.Left -and $x -le ($area.Right - 80) -and $y -ge $area.Top -and $y -le ($area.Bottom - 80)) {
            $window.Left = $x
            $window.Top = $y
        }
    }
    catch { Write-PetLog ('Position restore: ' + $_.Exception.Message) }
}

$script:DemoIndex = 0
$demoTimer = New-Object System.Windows.Threading.DispatcherTimer
$demoTimer.Interval = [TimeSpan]::FromMilliseconds(2300)
$demoActions = @('siu', 'calma', 'meditate', 'shirt', 'bicycle')
$demoTimer.Add_Tick({
    Switch-PetSkin
    Start-PetAnimation -Name $demoActions[$script:DemoIndex] -Force
    $script:DemoIndex = ($script:DemoIndex + 1) % $demoActions.Count
})

$window.Add_ContentRendered({
    try {
        if (-not [CR7PetNative.KeyboardHook]::Install()) {
            Write-PetLog 'Global shortcut hook could not be installed.'
        }
        $script:LastHookCounter = [CR7PetNative.KeyboardHook]::SwitchCounter
        $script:LastSiuCounter = [CR7PetNative.KeyboardHook]::SiuCounter
        $script:LastBicycleCounter = [CR7PetNative.KeyboardHook]::BicycleCounter
        try {
            $snapshot = [CR7PetNative.Sensors]::ReadAudio()
            $script:LastVolume = $snapshot.Volume
            $script:LastMuted = $snapshot.Muted
        }
        catch { Write-PetLog ('Initial audio: ' + $_.Exception.Message) }
        $initialBrightness = [CR7PetNative.Sensors]::ReadBrightness()
        if ($initialBrightness -ge 0) { $script:LastBrightness = $initialBrightness }
        $script:CodexWasRunning = @(Get-Process -Name 'ChatGPT', 'codex' -ErrorAction SilentlyContinue).Count -gt 0

        foreach ($timer in @($animationTimer, $hookTimer, $volumeTimer, $brightnessTimer, $codexTimer, $focusTimer, $confirmationTimer)) {
            $timer.Start()
        }
        Start-PetAnimation -Name 'bicycle' -Force
        if ($Demo) { $demoTimer.Start() }
        Write-PetLog ('Shown WPF handle-ready location={0},{1} skin={2} debug={3}' -f $window.Left, $window.Top, $script:SkinNames[$script:SkinIndex], $DebugWindow)
    }
    catch {
        Write-PetLog ('Startup: ' + $_.Exception.ToString())
        throw
    }
})

if ($DebugWindow) {
    $window.ShowInTaskbar = $true
    $root.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(180, 28, 31, 40))
}

$window.Add_Closed({
    foreach ($timer in @($animationTimer, $hookTimer, $volumeTimer, $brightnessTimer, $codexTimer, $focusTimer, $confirmationTimer, $bubbleTimer, $singleClickTimer, $demoTimer)) {
        $timer.Stop()
    }
    [CR7PetNative.KeyboardHook]::Uninstall()
    try {
        [pscustomobject]@{
            x = [math]::Round($window.Left)
            y = [math]::Round($window.Top)
            skinIndex = $script:SkinIndex
        } | ConvertTo-Json | Set-Content -LiteralPath $script:StatePath -Encoding UTF8
    }
    catch { Write-PetLog ('State save: ' + $_.Exception.Message) }
    if ($createdNew) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
})

try {
    $application = New-Object System.Windows.Application
    $application.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
    $application.Run($window) | Out-Null
}
catch {
    Write-PetLog ('Fatal: ' + $_.Exception.ToString())
    [CR7PetNative.KeyboardHook]::Uninstall()
    throw
}
