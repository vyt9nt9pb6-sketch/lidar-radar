# Forward Radar

[繁體中文](README.md)

While you walk looking down at your phone, LiDAR measures how far the nearest thing ahead is. The distance shows in the Dynamic Island, with haptics and a sound. After monitoring starts, you do not need to tap.

The interface follows the phone language. Traditional Chinese (`zh-Hant`) shows Chinese. Every other language shows English. Change it in Settings → General → Language & Region.

Open the blue `LidarRadar.xcodeproj` in Xcode. You do not need to write code.

## What cannot keep running

**When another app is in front, or the phone is locked, LiDAR stops.** That is an iOS limit. Come back to Forward Radar and it measures again on its own. Until then, the Dynamic Island and Lock Screen say Paused.

These are the ways a camera can stay on while another app is in front. None of them is a legal fit for this walking radar on iPhone, so none of them is implemented:

- **ARKit cannot.** This app reads LiDAR with ARKit `sceneDepth`. At WWDC22 Apple said ARKit does not support the camera while multitasking. Switching apps, Split View, or locking the phone interrupts the ARSession. There is no switch that turns that off.
- **The AVFoundation LiDAR camera cannot, unless the app is a calling app.** Since iOS 15.4, `AVCaptureDevice.DeviceType.builtInLiDARDepthCamera` can deliver depth, but it follows the same background rule as any camera. On iPhone, `AVCaptureSession.isMultitaskingCameraAccessSupported` is true only if the app is linked against iOS 18 or later **and** lists `voip` in background modes, or if Apple has granted `com.apple.developer.avfoundation.multitasking-camera-access`. The `voip` mode is for internet calls. Using it so a walking radar can keep the camera would be rejected on the App Store. The entitlement has to be requested from Apple. A free personal Apple ID cannot sign it, so the app would not install.
- **Picture in Picture keeps a card, not the camera.** Settings has an experiment that is off by default: “Experimental floating window”. When it is on, leaving the app tries to keep a drawn distance card on screen with `AVPictureInPictureController` and an `AVSampleBufferDisplayLayer` content source (iOS 15+). It does **not** keep LiDAR measuring. The video-call style of PiP, which can keep a camera preview, still needs the multitasking-camera gate above. This is not a calling app, and it does not pretend to be one.
- **The iPad Stage Manager exception does not apply.** Some iPads can use the camera while multitasking in Stage Manager with an extended display, without that special entitlement. This project is iPhone only. ARKit still does not support multitasking camera use on iPad.

Distance measurement is not switched to a background session, and the project does not add `voip` or that entitlement. On a normal iPhone, after you leave, the floating card (if the experiment is on) and the Dynamic Island both say paused. Measuring resumes when you come back.

At runtime the app reads `AVCaptureSession.isMultitaskingCameraAccessSupported` and whether any depth frame arrives after the app leaves the foreground. With no new frame, the card draws “Paused” and “Tap to return”. It does not keep the last meters. A live distance, danger color, and emoji are drawn only when a new frame actually arrives, and only then do haptics and sound continue.

The `builtInLiDARDepthCamera` path is `LidarRadar/AR/LiDARMultitaskingCapture.swift`. The whole file is inside the compile flag `LIDAR_MULTITASKING_CAPTURE`, which is **off**. If Apple grants `com.apple.developer.avfoundation.multitasking-camera-access`, add that entitlement to `LidarRadar.entitlements` and add `LIDAR_MULTITASKING_CAPTURE` to the app target’s Swift Active Compilation Conditions. Adding the entitlement without a grant makes a free Apple ID fail to sign, and the app will not install. Do not add `voip`. When the flag is on and the system reports support, ranging uses that AVFoundation path, because ARKit still will not deliver depth while multitasking. When the system reports no support, the app stays on ARKit.

## What you need

- A Mac with **Xcode 15 or later**
- A data cable, or wireless debugging already paired
- **iOS 16.2 or later** on the iPhone (the project installs on iOS 16.1, but the stable Live Activity API needs 16.2; on 16.1 you still get sound, haptics, and the large number, plus a note to update)
- To actually measure: **iPhone 12 Pro, 12 Pro Max, 13 Pro, 13 Pro Max, or a later Pro / Pro Max with LiDAR**
- To see the Dynamic Island: **iPhone 14 Pro or later**. 12 Pro and 13 Pro still get the Lock Screen Live Activity, sound, and haptics
- Phones without LiDAR can install the app. They see an explanation and the app does not crash. The Simulator has no LiDAR and shows that same screen

A free Apple ID can run the app on your own phone. You reinstall about every 7 days. A paid developer account is not required.

## 1. Open the project

1. Copy this folder to the Mac.
2. Double-click the blue **LidarRadar.xcodeproj**.
3. Wait for indexing. The scheme at the top left must be **LidarRadar**, not LidarRadarWidget.

Only if `LidarRadar.xcodeproj` is missing, generate it. In Terminal, from this folder:

```bash
brew install xcodegen
xcodegen generate
```

Install Homebrew from [https://brew.sh](https://brew.sh) if you need it. Then double-click `LidarRadar.xcodeproj`.

If Xcode asks to perform changes or update project settings, choose Perform Changes.

## 2. Set the signing team

The first Run usually fails until an account is selected. Do this for **both** targets.

1. In the left sidebar, click the blue **LidarRadar** icon at the top.
2. Under TARGETS, click **LidarRadar**.
3. Open **Signing & Capabilities**.
4. Leave **Automatically manage signing** on.
5. Set **Team** to your name. If it says None: Xcode → Settings… → Accounts → the plus button → Apple ID. Come back and choose Personal Team.
6. Click **LidarRadarWidget** under TARGETS and repeat steps 3 to 5 with the **same** team.

If the widget has no team, the app will not install even when the app target is signed.

## 3. Change the bundle ID if you need to

Defaults:

- App: `com.kwok.lidarradar`
- Widget: `com.kwok.lidarradar.widget`

If Xcode says the identifier is already in use, change both. The widget **must** be the app identifier plus `.widget`.

1. Stay on Signing & Capabilities.
2. Select the LidarRadar target and set Bundle Identifier, for example `com.yourname.lidarradar`.
3. Select LidarRadarWidget and set `com.yourname.lidarradar.widget`.
4. Keep the same team.

You can also edit `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, then run `xcodegen generate`.

## 4. Run on an iPhone

1. On the iPhone, turn on Developer Mode: Settings → Privacy & Security → Developer Mode → on → restart → confirm. Without this, Xcode cannot install on iOS 16 or later.
2. Plug in the iPhone, unlock it, and tap Trust if asked.
3. In the device menu at the top of Xcode, choose your **iPhone**. Do not choose a Simulator.
4. Confirm the scheme is **LidarRadar**.
5. Press the **Run** triangle (or ⌘R).
6. The first build takes a while. The phone should open Forward Radar.
7. If the phone says Untrusted Developer: Settings → General → VPN & Device Management → trust the developer app, then Run again.

A yellow warning with Build Succeeded can be ignored. A red error should stop you.

## 5. First launch

1. Read the three principles, turn on the agreement switch, then tap Agree and start monitoring. The camera stays off until you agree.
2. Allow the camera. LiDAR uses camera permission.
3. Location may be asked next. You can deny it. Denying it does not stop measuring while this app is on screen. Location is only a brief help when you switch away, and coordinates are not saved.
4. Point the back of the phone forward. The large number is meters.
5. For the Dynamic Island: Settings → Forward Radar → Live Activities. Also check Settings → Face ID & Passcode → Allow Access When Locked → Live Activities.
6. While monitoring, the screen does not auto-lock, because locking would turn the camera off. Pressing the side button still pauses measuring.

Thresholds:

- Green, safe: 1.5 meters or more
- Yellow, caution: under 1.5 meters
- Red, danger: under 0.8 meters

Green does not beep. Yellow and red vibrate and play a sound together. By default the sound plays even when the mute switch is on. Turn off “Play even when muted” in the app’s settings to change that.

## How the requirements are met

1. **Passive monitoring.** After consent and camera permission, LiDAR runs without another tap. Alerts are in the Dynamic Island, with a large distance, sound, and haptics.
2. **iOS only.** Swift, SwiftUI, ARKit, ActivityKit.
3. **LiDAR check.** `supportsFrameSemantics(.sceneDepth)` decides whether distance can be measured. `supportsSceneReconstruction(.mesh)` is shown on the explanation screen. Unsupported phones stay on that screen and do not crash. If Live Activities are off, or the system is still on iOS 16.1, the app says so and keeps sound, haptics, and the number.
4. **Metal distance.** Each depth frame and its confidence map are copied to the GPU. `DepthReduction.metal` finds the minimum in the forward center. It is not a CPU loop over pixels. The center matches the camera’s optical axis. Pixels below medium confidence are dropped. Updates are about every frame, or 15 per second in low-power mode, system Low Power Mode, or when the phone is hot. Work stays off the main thread.
5. **Dynamic Island.** ActivityKit starts the Live Activity. The widget extension draws the Lock Screen and the compact, minimal, and expanded Dynamic Island. `RadarAttributes.ContentState` carries distance, level, paused, low power, time, and a short status line. Updates go out on a level change, or when distance moves by at least 0.25 meters and 2 seconds have passed, plus a heartbeat about every 15 seconds.
6. **One danger model.** `Shared/DangerLevel.swift` is compiled into the app and the widget. Thresholds, colors, emoji, labels, haptic strength, and tone are that one file. Strings come from `Shared/Localizable.xcstrings`, also in both targets.
7. **What continues, and what does not.** `Info.plist` has audio and location background modes. Entering the background starts a short background task, marks the Live Activity paused, then ends the task. `sessionWasInterrupted` and `sessionInterruptionEnded` resume tracking. The app does not call `pause()` on a system interruption, or the resume callback would not arrive. With the floating-window experiment on, backgrounding does not tear down the audio session, because PiP needs it, and `canStartPictureInPictureAutomaticallyFromInline` is set so the card can leave with you. Control Center and the notification shade do not force the window open; they only switch the card to paused. The background task ends after one check that no new depth frame arrived. See the section at the top: on a normal iPhone, LiDAR does not keep measuring behind another app or on the lock screen.

### How to try the floating window

1. Install on an iPhone with LiDAR, agree, and start monitoring so a distance is on screen.
2. Open the gear → turn on “Experimental floating window”. The footer says whether this phone’s `isMultitaskingCameraAccessSupported` is true. A build signed with a free Apple ID should say it is not.
3. Return to the radar. A card appears under the status. That is the preview of the floating window, not the camera. It should change color with the distance. “The window can start when you leave the app” means the system will try to take it with you. “The system is not allowing the window yet” often means Low Power Mode; turn that off and try again.
4. Go to the Home Screen or open another app. Do not only pull down Control Center. A floating window should appear.
5. On a normal iPhone the window should say **Paused** and **Tap to return**. The meters should not keep changing. The Dynamic Island and Lock Screen Live Activity should say paused. Haptics and sound should stop.
6. Tap the window to return. Distance should update again on its own.
7. Turn the experiment off and leave again. No floating window. The Live Activity still says paused.

If the window keeps showing new meters, depth frames are still arriving after you left. The settings footer should then say this iPhone reports background camera access. Without that sentence, a live distance should not appear.
8. **Privacy.** First launch requires agreement before the camera, location, or a Live Activity. The three principles are processed on this iPhone, never uploaded, never stored. Depth, distance, and location are not written to a file. UserDefaults stores only consent and settings. `PrivacyInfo.xcprivacy` says nothing is collected or tracked, and declares UserDefaults with reason `CA92.1`. Settings can revoke consent: UserDefaults is cleared, Live Activities end, and the agreement returns. The same screen opens iOS Settings for camera and location. Permission text is in `InfoPlist.strings` for English and Traditional Chinese. `NSSupportsLiveActivities` is set.

## Files

- `LidarRadar/`: the app. `PiP/` is the experimental floating window. `AR/LiDARMultitaskingCapture.swift` is not compiled by default.
- `LidarRadarWidget/`: Dynamic Island and Lock Screen
- `Shared/`: `DangerLevel`, `RadarAttributes`, `L10n`, and `Localizable.xcstrings`
- `LidarRadar/en.lproj` and `zh-Hant.lproj`: permission strings. The widget has the same folders for the display name
- `LidarRadar/Shaders/DepthReduction.metal`: the GPU minimum
- `project.yml`: XcodeGen spec. Development language is English
- `LidarRadar.xcodeproj`: open this
- `scripts/generate_xcodeproj.py`: only needed to regenerate the project without a Mac

Bundle IDs are `com.kwok.lidarradar` and `com.kwok.lidarradar.widget`. The deployment target is iOS 16.1.
