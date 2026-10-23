# 前方雷達

[English](README.en.md)

低頭看手機走路時，用 iPhone 的光達看前方還有多遠。距離會出現在螢幕最上方的動態島，同時用震動和聲音提醒。監測開始之後，不用再點畫面。

介面跟著手機語言。手機是繁體中文就顯示繁體中文，其他語言顯示英文。要改的話：設定 → 一般 → 語言與地區。

這個專案已經可以用 Xcode 打開。你不需要會寫程式。

## 請先知道這件事

**別的 App 在畫面上，或手機鎖定時，光達一定會停。** 這是 iOS 的限制，不是故障。回到「前方雷達」之後，它會自己繼續量，不用再按開始。這段時間動態島和鎖定畫面會改顯示「已暫停」。

查過可以讓相機在背景繼續的做法，沒有一種能合法用在這支 iPhone 的走路雷達上：

- **ARKit 不行。** 這個 App 用 ARKit 的 `sceneDepth` 讀光達。Apple 在 WWDC22 寫明：ARKit 不支援多工時使用相機。切到別的 App、分割畫面、或鎖定，系統都會中斷 ARSession。沒有開關可以關掉這個限制。
- **AVFoundation 的光達相機也不行，除非你是通話 App。** iOS 15.4 之後可以用 `AVCaptureDevice.DeviceType.builtInLiDARDepthCamera` 拿深度，但背景規則跟一般相機一樣。`AVCaptureSession.isMultitaskingCameraAccessSupported` 在 iPhone 上只有兩種情況會是 true：App 連結 iOS 18 以上**而且**背景模式包含 `voip`，或是 Apple 另外核准的 entitlement `com.apple.developer.avfoundation.multitasking-camera-access`。`voip` 是給網路電話用的，拿來讓走路雷達繼續開相機會被 App Store 拒絕。那個 entitlement 要向 Apple 申請，個人的免費 Apple ID 簽不了名，簽了也裝不進手機。
- **子母畫面留得住的是一張卡片，不是相機。** 設定裡有一個預設關掉的實驗：「實驗：子母畫面」。打開之後，離開 App 時會試著用 `AVPictureInPictureController` 把一張自己畫的距離卡片留在畫面上（`AVSampleBufferDisplayLayer`，iOS 15 以上）。它**不會**讓光達繼續量。視訊通話那種能把相機留在小窗裡的做法，仍然要上面的多工相機資格。這不是通話 App，也沒有用假的 VoIP。
- **iPad 的 Stage Manager 例外不適用。** 部分 iPad 在外接螢幕的 Stage Manager 下，相機多工不用那個特殊 entitlement。這個專案只做 iPhone。而且就算在 iPad 上，ARKit 仍然不支援多工相機。

所以測距沒有改成背景繼續跑，也沒有加 `voip` 或那個 entitlement。一般 iPhone 切走之後，小窗（若有打開實驗）和動態島都會寫已暫停，回來再量。

程式會在執行時看兩件事：`AVCaptureSession.isMultitaskingCameraAccessSupported`，以及離開前景之後有沒有新的深度幀。沒有新幀時，小窗只畫「已暫停」和「點一下回到 App」，不會把離開前的公尺數留在畫面上。有新幀（只有系統真的還在出深度時才會發生）才改畫即時距離、危險顏色和表情，並繼續震動與聲音。

`builtInLiDARDepthCamera` 的程式在 `LidarRadar/AR/LiDARMultitaskingCapture.swift`，整份包在編譯旗標 `LIDAR_MULTITASKING_CAPTURE` 裡，**預設不編譯**。Apple 如果核准了 `com.apple.developer.avfoundation.multitasking-camera-access`，才把該 entitlement 加進 `LidarRadar.entitlements`，並在主 App target 的 Swift Active Compilation Conditions 加上 `LIDAR_MULTITASKING_CAPTURE`。沒有核准就加 entitlement，免費 Apple ID 會簽不了名、裝不進手機。不要加 `voip`。旗標打開且系統回報支援時，測距改走這條 AVFoundation 路徑（ARKit 在多工時仍然不會出深度）；系統回報不支援時，仍用 ARKit。

背景模式（聲音、定位）只用來把這句「已暫停」送出去，以及播放很短的提示音。它們不能讓光達在口袋裡或在別的 App 前面繼續跑。

## 你需要準備

- 一台 Mac，安裝 **Xcode 15 或更新版本**（Xcode 16、Xcode 26 都可以）
- 一條可以傳資料的線，或已配對的無線除錯
- iPhone 系統 **iOS 16.2 或更新**（專案最低可安裝在 iOS 16.1，但動態島的穩定介面需要 16.2。停在 16.1 時，App 仍會用聲音、震動和畫面上的大字，並請你更新系統）
- 要真的量到距離：**iPhone 12 Pro、12 Pro Max、13 Pro、13 Pro Max，或之後有光達的 Pro / Pro Max**
- 要看到動態島：還需要 **iPhone 14 Pro 或更新、有動態島的機型**。12 Pro 和 13 Pro 沒有動態島，警示會改出現在鎖定畫面，聲音和震動仍然有
- 沒有光達的 iPhone 也可以安裝。打開後會看到說明，不會閃退。模擬器沒有光達，也只會看到這段說明

免費的 Apple ID 就可以在自己的手機上跑，大約 7 天要重新安裝一次。不需要付費開發者帳號。

## 1. 打開專案

1. 把這個資料夾放到 Mac 上（AirDrop、iCloud、或 Git 都可以）。
2. 找到藍色圖示 **LidarRadar.xcodeproj**，雙擊。
3. 等 Xcode 把索引跑完。左上角的 Scheme 請選 **LidarRadar**，不要選 LidarRadarWidget。

如果資料夾裡沒有 `LidarRadar.xcodeproj`，才需要自己產生一次。打開「終端機」，進到這個資料夾，執行：

```bash
brew install xcodegen
xcodegen generate
```

沒有 Homebrew 的話，先到 [https://brew.sh](https://brew.sh) 安裝。產生完再雙擊 `LidarRadar.xcodeproj`。

Xcode 若問要不要 “Perform Changes” 或更新專案設定，按 Perform Changes 即可。

## 2. 設定簽名（Team）

第一次按執行，多半會因為還沒選帳號而失敗。照下面做，**兩個 target 都要做**。

1. Xcode 最左邊，點最上面的藍色圖示 **LidarRadar**。
2. 中間偏左會看到 PROJECT 和 TARGETS。
3. 在 TARGETS 底下先點 **LidarRadar**。
4. 上方點 **Signing & Capabilities**。
5. 勾著 **Automatically manage signing**。
6. **Team** 選你的名字。若寫著 None：選單 Xcode → Settings… → Accounts → 左下角加號 → Apple ID，登入後回到這裡再選 Personal Team。
7. 再點 TARGETS 裡的 **LidarRadarWidget**，重複第 4 到第 6 步，Team 選**同一個**。

Widget 沒選 Team 的話，主 App 就算簽好了也裝不進手機。

## 3. 若要改 Bundle ID

預設是：

- 主 App：`com.kwok.lidarradar`
- Widget：`com.kwok.lidarradar.widget`

若 Xcode 說這個識別碼已被使用，兩個都要改，而且 **Widget 必須是「主 App 的識別碼」後面加上 `.widget`**。

1. 還是在 Signing & Capabilities。
2. TARGETS 選 LidarRadar，把 Bundle Identifier 改成你自己的，例如 `com.你的英文名.lidarradar`。
3. TARGETS 選 LidarRadarWidget，改成 `com.你的英文名.lidarradar.widget`。
4. Team 仍選同一個。

也可以改專案裡的 `project.yml`（搜尋 `PRODUCT_BUNDLE_IDENTIFIER`），存檔後在終端機執行 `xcodegen generate`，再重新打開 Xcode。

## 4. 裝到 iPhone

1. iPhone 先打開開發者模式：設定 → 隱私權與安全性 → 開發者模式 → 打開 → 重新開機 → 再確認打開。iOS 16 之後沒做這步，Xcode 會裝不上去。
2. 用線接上 iPhone，解鎖，若問「要信任這部電腦嗎」點信任。
3. Xcode 上方正中間，裝置選你的 **iPhone**。不要選任何 “Simulator”。
4. 左上角 Scheme 確認是 **LidarRadar**。
5. 按左上角的三角形 **Run**（或按鍵盤 ⌘R）。
6. 第一次編譯會比較久。成功的話，手機上會自己打開「前方雷達」。
7. 若手機說「未受信任的開發者」：設定 → 一般 → VPN 與裝置管理 → 開發者 App → 信任，然後回 Xcode 再按一次 Run。

## 5. 第一次打開 App

1. 閱讀三個原則，打開「我已閱讀，並同意」，再按「同意並開始監測」。沒同意就不會開相機。
2. 系統問相機時選 **允許**。光達走的是相機權限。
3. 接著可能問定位。可以選不允許。不允許也不影響你看著 App 時的測距。定位只是背景切換時的輔助，座標不會被存下來。
4. 把手機背面朝向前方。中間的大字是最近的距離，單位是公尺。
5. 若要動態島：設定 → 前方雷達 → 打開「即時動態」。也可以看設定 → 臉部辨識與密碼 → 鎖定時允許取用 → 即時動態。
6. 監測中螢幕不會自動鎖定，否則 iOS 會把相機關掉。你自己按側邊按鈕鎖定時，監測會暫停。

安全、注意、危險的距離是：

- 綠色安全：1.5 公尺（含）以上
- 黃色注意：小於 1.5 公尺
- 紅色危險：小於 0.8 公尺

綠色只顯示顏色，不會一直響。黃色和紅色會同時震動和出聲。聲音預設在靜音開關關掉時也會響，可在 App 的設定裡關掉「即使靜音也播放」。

## 各項需求怎麼做

### 1. 被動監測、主動警示

同意並允許相機之後，光達自己開始跑，不需要再按開始。警示在動態島（視線邊緣），App 裡也有很大的公尺數字。聲音和震動一起發出，不看螢幕也收得到。

### 2. 只做 iOS

Swift、SwiftUI、ARKit、ActivityKit。沒有 Android 版。

### 3. 光達與沒有動態島時

程式用 `ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)` 判斷能不能量距離，並一併讀取 `supportsSceneReconstruction(.mesh)` 顯示在說明畫面上。沒有光達就停在說明頁，不呼叫會失敗的相機設定，所以不會閃退。

即時動態若被關掉、或系統是 iOS 16.1 還沒有新的 ActivityContent 介面，App 會寫清楚原因，聲音、震動和畫面數字繼續工作。沒有動態島的手機仍可使用鎖定畫面的即時動態；動態島的 compact、minimal、expanded 三種版面都有做，系統會自己決定用哪一種。

### 4. 即時距離，用 Metal 算

每一幀的深度圖（公尺）和信心圖會整塊複製到 GPU。`DepthReduction.metal` 用平行運算找出前方中央區域的最小值，不是用 CPU 一格一格算。中央區域對應相機光軸，也就是手機背面正對的方向。信心低於中等的像素會被丢掉。

一般情況盡量每一幀都算（光達大約每秒 60 次）。省電模式、系統低耗電模式，或手機溫度偏高時，自動降成每秒 15 次。計算在 ARSession 的背景佇列和另一條 Metal 佇列，不會卡住主畫面。

### 5. 動態島

主 App 用 ActivityKit 啟動即時動態。Widget Extension 提供鎖定畫面，以及動態島的 compact、minimal、expanded。資料型別是 `RadarAttributes`，裡面的 `ContentState` 有距離、危險等級、是否暫停、是否省電、時間和一句狀態文字。

等級變了會立刻更新。距離要差至少 0.25 公尺，而且距上次至少 2 秒，才會再推一次。另外大約每 15 秒送一次心跳，避免系統把還在監測的活動當成過期。這樣才不會把 ActivityKit 的更新額度一下用完。

### 6. 同時用看、震、聽

`Shared/DangerLevel.swift` 同時編譯進主 App 和 Widget。門檻、顏色、表情符號、中文等級、震動強度、提示音頻率都只有這一份。

危險是較重、較密的觸覺（Core Haptics，失敗時改用系統震動）加上較高的提示音。注意較輕、較疏。安全不發聲。聲音是程式產生的短音，沒有另外夾音檔。

### 7. 持續執行，以及 iOS 的上限

`Info.plist` 有 `UIBackgroundModes` 的 `audio` 和 `location`。進入背景時會 `beginBackgroundTask`，把動態島改成暫停，然後把背景時間還給系統。

ARSession 有 `sessionWasInterrupted` 和 `sessionInterruptionEnded`。系統中斷時不會再呼叫 `pause()`，否則收不到恢復通知。回到前景或中斷結束後會自動 `run`。

子母畫面實驗打開時，進入背景不會把聲音工作階段關掉（系統要播得起小窗），並用 `canStartPictureInPictureAutomaticallyFromInline` 讓小窗跟著切走自動出現。拉下控制中心或通知中心只會先把卡片改成暫停，不會在那個當下強制彈出小窗。背景任務在確認過一次「沒有新幀」之後就還給系統。小窗本身不能讓光達繼續跑。

再次說明：別的 App 在前景、鎖定或背景時，一般 iPhone 的光達不會繼續量。即時動態顯示暫停。沒有使用 voip 背景模式，也沒有加入多工相機 entitlement。原因見最上面的「請先知道這件事」。

### 怎麼試子母畫面

1. 用有光達的 iPhone 裝上 App，同意並開始監測，確認畫面上有距離。
2. 右上角齒輪 → 打開「實驗：子母畫面」。說明文字會告訴你這支手機的 `isMultitaskingCameraAccessSupported` 是不是 true。免費 Apple ID 裝的版本，這裡幾乎一定是不支援。
3. 回到雷達畫面。監測區下方會多一張卡片，那是小窗的預覽，不是相機畫面。它應跟著距離變色。下面若寫「離開 App 時可以開小窗」，代表系統願意把它帶出去。若寫「系統還沒允許開小窗」，先關掉低耗電模式再試一次。
4. 滑到主畫面或打開另一個 App（不要只拉下控制中心）。應出現一個浮動小窗。
5. 在一般 iPhone 上，小窗應寫 **已暫停**，下面寫 **點一下回到 App**。不應繼續跳公尺數。動態島和鎖定畫面的即時動態也應是已暫停。震動和聲音應停。
6. 點小窗回到「前方雷達」，距離應自己繼續更新。
7. 關掉實驗後再切走，不應再出現小窗，行為跟以前一樣：動態島暫停。

若小窗竟然繼續顯示新的公尺數，代表離開之後仍有深度幀進來。請看設定頁的說明是不是改成「這支 iPhone 回報背景可以使用相機」。沒有那句話時，不應出現活的距離。

### 8. 隱私

第一次打開必須同意，否則不開相機、不定位、不起動態島。畫面上的三個原則是：**只在手機上處理、從不上傳、從不儲存**。

深度、距離、位置都不寫進檔案。本機的 UserDefaults 只記「已同意」和設定開關。`PrivacyInfo.xcprivacy` 宣告沒有蒐集資料、沒有追蹤，並以理由碼 `CA92.1` 說明使用了 UserDefaults。

設定裡可以清除同意與所有資料：刪掉 UserDefaults、結束即時動態、回到同意畫面。同一頁可以打開 iOS 設定，撤銷相機或定位權限。

相機、定位、動作感測器的用途說明有繁體中文和英文（`en.lproj` 與 `zh-Hant.lproj` 的 `InfoPlist.strings`），也包含 `NSSupportsLiveActivities`。動作感測器是光達追蹤方向用的，沒有這段說明，部分 iOS 版本會在打開相機時直接閃退。

介面、同意書、動態島和權限說明都走 `Shared/Localizable.xcstrings`，開發語言是英文，所以手機不是繁體中文時會看到英文。主 App 和 Widget 各打一份同一份字串目錄。

## 常見問題

**模擬器上一片黑或只有說明。** 模擬器沒有光達。請改選真的 iPhone。

**Signing requires a development team。** 回到第 2 節，兩個 target 都選 Team。

**Failed to register bundle identifier。** 回到第 3 節改掉 Bundle ID。

**裝上去立刻閃退，並提到相機或定位說明。** 確認 `Info.plist` 還在主 App target 裡，沒有被清掉。正常情況下已經設好了。

**有距離，但沒有動態島。** 確認是 14 Pro 或更新的機型，系統至少 iOS 16.2，而且設定裡「前方雷達」的即時動態是開的。沒有動態島時，鎖定手機看鎖定畫面的即時動態。

**鎖定或切到別的 App 之後數字不更新。** 這是預期行為。回到「前方雷達」就會繼續。實驗用的子母畫面只留一張卡片；一般 iPhone 上它會寫已暫停，不會繼續量。見上面的「怎麼試子母畫面」。

**想改成英文或中文。** 跟著手機語言。設定 → 一般 → 語言與地區。不是繁體中文的語言會看到英文。

**Xcode 出現黃色警告，但最後寫著 Build Succeeded。** 可以忽略，直接看手機有沒有打開 App。黃色不是錯誤。紅色 Error 才需要停下來。

**想確認震動和聲音。** 打開 App 右上角齒輪 → 試播危險警示。

## 專案裡有什麼

- `LidarRadar/`：主 App。畫面、光達、Metal、聲音震動、即時動態的發送、隱私設定。`PiP/` 是實驗用子母畫面。`AR/LiDARMultitaskingCapture.swift` 預設不編譯。
- `LidarRadarWidget/`：Widget Extension。動態島和鎖定畫面。
- `Shared/`：兩邊共用的危險等級、`RadarAttributes`，以及 `Localizable.xcstrings`（英文與繁體中文）。
- `LidarRadar/en.lproj`、`LidarRadar/zh-Hant.lproj`：相機、定位、動作感測器的權限說明。
- `README.en.md`：同一份說明的英文版。
- `LidarRadar/Shaders/DepthReduction.metal`：GPU 上的最小值運算。
- `project.yml`：XcodeGen 的專案描述。
- `LidarRadar.xcodeproj`：已經產生好、可直接打開的 Xcode 專案。
- `scripts/generate_xcodeproj.py`：沒有 Mac 時用來產生同一份專案檔和圖示的工具。一般不需要執行。

主 App 的 Bundle ID 是 `com.kwok.lidarradar`，Widget 是 `com.kwok.lidarradar.widget`。部署目標是 iOS 16.1。
